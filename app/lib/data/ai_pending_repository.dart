/// AI 离线任务队列的本地存储。
///
/// 无外网时把「AI 对话请求」与「待识别的支付截图」排进队列，联网后重放。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/utils.dart';
import 'db/database.dart';

/// 把待识别的截图落到应用文档目录，返回文件路径。
///
/// 放在队列这一层，是因为它的唯一用途就是给离线任务留存待识别的图片。
Future<String> persistPendingScreenshot(
  Uint8List bytes, {
  String mimeType = 'image/jpeg',
}) async {
  final dir = await getApplicationDocumentsDirectory();
  final extension = mimeType == 'image/png' ? 'png' : 'jpg';
  final file = File(
    p.join(dir.path, 'pending-receipt-${newId()}.$extension'),
  );
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// 队列任务类型。
enum PendingTaskType {
  /// 一句等待 AI 回答的对话消息
  chat,

  /// 一张等待识别的支付截图
  vision;

  static PendingTaskType parse(String value) =>
      values.firstWhere((item) => item.name == value, orElse: () => chat);

  String get label => switch (this) {
        chat => '对话消息',
        vision => '支付截图',
      };
}

enum PendingTaskStatus {
  /// 等待联网重放
  pending,

  /// 正在重放
  running,

  /// 识图已出结果，等待用户确认入账
  awaiting,

  done,

  /// 重放失败（保留在队列里，可手动重试）
  failed;

  static PendingTaskStatus parse(String value) =>
      values.firstWhere((item) => item.name == value, orElse: () => pending);

  /// 还需要用户或系统处理的状态。
  bool get needsAttention =>
      this == pending || this == running || this == awaiting || this == failed;

  String get label => switch (this) {
        pending => '待联网',
        running => '处理中',
        awaiting => '待确认',
        done => '已完成',
        failed => '失败',
      };
}

class PendingTask {
  const PendingTask({
    required this.id,
    required this.type,
    required this.status,
    required this.retryCount,
    required this.createdAt,
    this.payloadJson,
    this.imagePath,
    this.lastError,
  });

  final String id;
  final PendingTaskType type;
  final PendingTaskStatus status;
  final int retryCount;
  final DateTime createdAt;
  final String? payloadJson;
  final String? imagePath;
  final String? lastError;

  Map<String, dynamic> get payload => decodePayload(payloadJson);
}

/// 宽松地解析 payload；损坏时按空对象处理，不让页面崩掉。
Map<String, dynamic> decodePayload(String? json) {
  if (json == null || json.isEmpty) return const {};
  try {
    final decoded = jsonDecode(json);
    return decoded is Map<String, dynamic> ? decoded : const {};
  } on FormatException {
    return const {};
  }
}

class AiPendingRepository {
  AiPendingRepository(this._db);

  final AppDatabase _db;

  Stream<List<PendingTask>> watchAll() {
    final query = _db.select(_db.aiPendingTasks)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]);
    return query.watch().map(
          (rows) => [for (final row in rows) _toTask(row)],
        );
  }

  /// 还需要处理的任务（含待确认）。
  Stream<List<PendingTask>> watchOpen() => watchAll().map(
        (tasks) => [
          for (final task in tasks)
            if (task.status.needsAttention) task,
        ],
      );

  Future<List<PendingTask>> openTasks() async {
    final rows = await (_db.select(_db.aiPendingTasks)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
    final tasks = [for (final row in rows) _toTask(row)];
    return [
      for (final task in tasks)
        if (task.status.needsAttention) task,
    ];
  }

  Future<String> enqueue({
    required PendingTaskType type,
    String? payloadJson,
    String? imagePath,
  }) async {
    final now = DateTime.now();
    final id = newId();
    await _db.into(_db.aiPendingTasks).insert(
          AiPendingTasksCompanion.insert(
            id: id,
            createdAt: now,
            updatedAt: now,
            taskType: type.name,
            payloadJson: Value(payloadJson),
            imagePath: Value(imagePath),
            status: Value(PendingTaskStatus.pending.name),
          ),
        );
    return id;
  }

  Future<void> markStatus(
    String id,
    PendingTaskStatus status, {
    String? payloadJson,
    String? error,
    int? retryCount,
  }) async {
    await (_db.update(_db.aiPendingTasks)..where((t) => t.id.equals(id))).write(
      AiPendingTasksCompanion(
        status: Value(status.name),
        payloadJson: payloadJson == null ? const Value.absent() : Value(payloadJson),
        lastError: Value(error),
        retryCount: retryCount == null ? const Value.absent() : Value(retryCount),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> remove(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.aiPendingTasks)..where((t) => t.id.equals(id))).write(
      AiPendingTasksCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  /// 清掉已完成的任务，避免列表越积越长。
  Future<void> clearFinished() async {
    final now = DateTime.now();
    await (_db.update(_db.aiPendingTasks)
          ..where((t) => t.deletedAt.isNull() & t.status.equals(PendingTaskStatus.done.name)))
        .write(
      AiPendingTasksCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  PendingTask _toTask(AiPendingTask row) => PendingTask(
        id: row.id,
        type: PendingTaskType.parse(row.taskType),
        status: PendingTaskStatus.parse(row.status),
        retryCount: row.retryCount,
        createdAt: row.createdAt,
        payloadJson: row.payloadJson,
        imagePath: row.imagePath,
        lastError: row.lastError,
      );
}
