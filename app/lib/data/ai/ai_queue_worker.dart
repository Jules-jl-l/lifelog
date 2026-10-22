/// 离线队列重放：联网后把排队中的 AI 请求与支付截图补做掉。
library;

import 'dart:convert';
import 'dart:io';

import '../ai_pending_repository.dart';
import '../security_store.dart';
import 'ai_service.dart';
import 'deepseek_client.dart';
import 'image_draft.dart';

/// 一轮重放的结果。
class ReplayReport {
  const ReplayReport({this.succeeded = 0, this.failed = 0, this.awaiting = 0});

  /// 已完成回答的对话任务数
  final int succeeded;

  /// 重放失败的任务数
  final int failed;

  /// 已识别、等待用户确认入账的截图数
  final int awaiting;

  int get processed => succeeded + failed + awaiting;

  bool get isEmpty => processed == 0;

  String get summary {
    final parts = <String>[
      if (succeeded > 0) '已补答 $succeeded 条',
      if (awaiting > 0) '待确认 $awaiting 张截图',
      if (failed > 0) '失败 $failed 条',
    ];
    return parts.isEmpty ? '没有需要重放的任务' : parts.join(' · ');
  }
}

class AiQueueWorker {
  AiQueueWorker({
    required this.pending,
    required this.ai,
    required this.client,
    required this.security,
  });

  final AiPendingRepository pending;
  final AiService ai;
  final DeepSeekClient client;
  final SecurityStore security;

  /// 重放全部待办任务。
  ///
  /// 一旦遇到网络或凭据类错误就中止本轮 —— 后续任务必然同样失败，
  /// 剩下的任务保持「待联网」，等下次触发再试。
  Future<ReplayReport> replayAll() async {
    final apiKey = await security.readApiKey();
    if (apiKey == null || apiKey.isEmpty) return const ReplayReport();

    final tasks = await pending.openTasks();
    var succeeded = 0;
    var failed = 0;
    var awaiting = 0;

    for (final task in tasks) {
      // 待确认的截图交给用户处理，不重复识别
      if (task.status == PendingTaskStatus.awaiting) continue;

      await pending.markStatus(task.id, PendingTaskStatus.running);

      try {
        switch (task.type) {
          case PendingTaskType.chat:
            await _replayChat(task);
            await pending.markStatus(task.id, PendingTaskStatus.done);
            succeeded++;
          case PendingTaskType.vision:
            await _replayVision(task, apiKey);
            awaiting++;
        }
      } on DeepSeekException catch (error) {
        await pending.markStatus(
          task.id,
          PendingTaskStatus.failed,
          error: error.message,
          retryCount: task.retryCount + 1,
        );
        failed++;
        break;
      } catch (error) {
        await pending.markStatus(
          task.id,
          PendingTaskStatus.failed,
          error: '$error',
          retryCount: task.retryCount + 1,
        );
        failed++;
      }
    }

    return ReplayReport(succeeded: succeeded, failed: failed, awaiting: awaiting);
  }

  /// 把失败或待联网的任务放回队列，供用户手动重试。
  Future<void> retry(String id) =>
      pending.markStatus(id, PendingTaskStatus.pending);

  Future<void> _replayChat(PendingTask task) async {
    final payload = task.payload;
    final sessionId = payload['sessionId'];
    final text = payload['text'];
    if (sessionId is! String || text is! String) {
      throw StateError('队列任务缺少会话信息');
    }
    // 用户消息在入队前已经落库，重放时不要再存一次
    await ai.send(
      sessionId: sessionId,
      text: text,
      persistUserMessage: false,
    );
  }

  Future<void> _replayVision(PendingTask task, String apiKey) async {
    final path = task.imagePath;
    if (path == null) throw StateError('队列任务缺少截图文件');

    final file = File(path);
    if (!await file.exists()) throw StateError('截图文件已不存在');

    final bytes = await file.readAsBytes();
    final mimeType = task.payload['mimeType'] as String? ?? 'image/jpeg';

    final raw = await client.extractFromImage(
      apiKey: apiKey,
      imageBytes: bytes,
      mimeType: mimeType,
      instruction: imageExtractionInstruction,
    );

    final draft = ImageDraft.fromModelOutput(raw);
    if (draft == null || !draft.isUsable) {
      throw StateError('没能从截图里识别出可用信息');
    }

    await pending.markStatus(
      task.id,
      PendingTaskStatus.awaiting,
      payloadJson: jsonEncode({
        ...task.payload,
        'imageDraft': draft.toJson(),
      }),
    );
  }
}
