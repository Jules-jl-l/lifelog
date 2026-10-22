/// AI 助手服务：编排「模型调用 → 本地工具执行 → 回复」，并负责会话持久化。
///
/// 设计取舍：
/// - 文本记账由用户明确说出，直接落库（不做二次确认），回复里说明写了什么
/// - 识图记账由上层做「草稿 + 确认」，因为识别结果可能不准
/// - 没有网络或没配 Key 时自动降级到本地规则记账，记账流程不中断
library;

import 'dart:convert';

import '../../core/utils.dart';
import '../ai_pending_repository.dart';
import '../ai_repository.dart';
import '../db/database.dart';
import '../finance_repository.dart';
import '../health_repository.dart';
import '../security_store.dart';
import '../settings_repository.dart';
import '../study_repository.dart';
import 'deepseek_client.dart';
import 'local_intent.dart';
import 'toolset.dart';

/// 助手默认名字；用户可在 AI 页或「我的」里改名。
const defaultAssistantName = '小朝';

class AiReply {
  const AiReply({required this.content, this.usedLocalRules = false});

  final String content;
  final bool usedLocalRules;
}

/// 流式回复的一帧：正文增量与最终回复二选一。
class AiChunk {
  const AiChunk({this.delta, this.reply});

  /// 正文增量；工具调用轮或本地兜底时为空。
  final String? delta;

  /// 本轮结束时的完整回复（消息已落库）。
  final AiReply? reply;
}

class AiService {
  AiService({
    required this.client,
    required this.aiRepository,
    required this.pending,
    required this.finance,
    required this.health,
    required this.study,
    required this.settings,
    required this.security,
    this.defaultAccountId,
  });

  final DeepSeekClient client;
  final AiRepository aiRepository;
  final AiPendingRepository pending;
  final FinanceRepository finance;
  final HealthRepository health;
  final StudyRepository study;
  final SettingsRepository settings;
  final SecurityStore security;
  final String? defaultAccountId;

  ToolContext get _toolContext => ToolContext(
        finance: finance,
        health: health,
        study: study,
        settings: settings,
        defaultAccountId: defaultAccountId,
      );

  /// 用户给助手起的名字，未设置时回落到「小朝」。
  Future<String> assistantName() async {
    final value = (await settings.get(SettingKeys.assistantName))?.trim();
    return (value == null || value.isEmpty) ? defaultAssistantName : value;
  }

  Future<String?> apiKey() => security.readApiKey();

  /// 用首条消息生成会话标题。
  String titleFrom(String text) {
    final trimmed = text.trim().replaceAll('\n', ' ');
    return trimmed.length <= 14 ? trimmed : '${trimmed.substring(0, 14)}…';
  }

  /// 发送一条消息并返回助手回复（含会话持久化）。
  ///
  /// 这是流式接口的便捷封装：离线队列重放等只关心最终结果的场景用它。
  /// [persistUserMessage] 为 false 时不重复保存用户消息 —— 离线队列重放时会用到。
  Future<AiReply> send({
    required String sessionId,
    required String text,
    bool persistUserMessage = true,
  }) async {
    AiReply? reply;
    await for (final chunk in sendStream(
      sessionId: sessionId,
      text: text,
      persistUserMessage: persistUserMessage,
    )) {
      if (chunk.reply != null) reply = chunk.reply;
    }
    if (reply == null) throw StateError('助手没有返回内容');
    return reply;
  }

  /// 流式发送：先逐段吐出正文增量，最后给出完整回复。
  ///
  /// 工具调用轮不会产生正文增量，界面此时应保持「正在思考」状态。
  Stream<AiChunk> sendStream({
    required String sessionId,
    required String text,
    bool persistUserMessage = true,
  }) async* {
    final userText = text.trim();
    if (userText.isEmpty) throw ArgumentError('内容不能为空');

    if (persistUserMessage) {
      await aiRepository.addMessage(
        sessionId: sessionId,
        role: 'user',
        content: userText,
      );
    }

    final key = await security.readApiKey();
    if (key == null || key.isEmpty) {
      yield AiChunk(
        reply: await _localFallback(
          sessionId,
          userText,
          '还没有配置 DeepSeek API Key',
        ),
      );
      return;
    }

    final history = await aiRepository.messagesOnce(sessionId);
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': await _systemPrompt()},
      for (final message in history)
        if (message.role != 'system')
          {'role': message.role, 'content': message.content},
    ];

    try {
      // 工具调用允许连续多轮：模型每轮返回 tool_calls 就执行后继续追问，
      // 直到它给出纯文本回答或达到安全轮数上限。
      const maxToolRounds = 3;
      final answer = StringBuffer();

      for (var round = 0; round <= maxToolRounds; round++) {
        final roundText = StringBuffer();
        final calls = <ToolCall>[];

        await for (final chunk in client.streamChat(
          apiKey: key,
          messages: messages,
          tools: aiToolSpecs,
        )) {
          final delta = chunk.content;
          if (delta != null) {
            roundText.write(delta);
            answer.write(delta);
            yield AiChunk(delta: delta);
          }
          if (chunk.toolCalls != null) calls.addAll(chunk.toolCalls!);
        }

        if (calls.isEmpty || round == maxToolRounds) break;

        messages.add({
          'role': 'assistant',
          'content': roundText.toString(),
          'tool_calls': [
            for (final call in calls)
              {
                'id': call.id,
                'type': 'function',
                'function': {
                  'name': call.name,
                  'arguments': call.argumentsJson,
                },
              },
          ],
        });
        for (final call in calls) {
          messages.add({
            'role': 'tool',
            'tool_call_id': call.id,
            'content': await runTool(call, _toolContext),
          });
        }
      }

      final content = answer.toString().trim();
      if (content.isEmpty) {
        yield AiChunk(
          reply: await _localFallback(sessionId, userText, '模型没有返回内容'),
        );
        return;
      }

      await aiRepository.addMessage(
        sessionId: sessionId,
        role: 'assistant',
        content: content,
      );
      yield AiChunk(reply: AiReply(content: content));
    } on DeepSeekException catch (error) {
      // 网络/凭据类失败：简单指令用本地规则先记上，记不了就排队等联网重放
      yield AiChunk(
        reply: await _localFallback(
          sessionId,
          userText,
          error.message,
          canQueue: true,
        ),
      );
    }
  }

  /// 离线 / 未配置 Key 时的兜底：本地规则能记就记，记不了就排进离线队列。
  Future<AiReply> _localFallback(
    String sessionId,
    String userText,
    String reason, {
    bool canQueue = false,
  }) async {
    final parsed = parseBookkeeping(userText);

    if (parsed == null) {
      final queued = canQueue
          ? await pending.enqueue(
              type: PendingTaskType.chat,
              payloadJson: jsonEncode({
                'sessionId': sessionId,
                'text': userText,
              }),
            )
          : null;

      final content = queued == null
          ? '$reason。\n'
              '本地规则也没能从这句话里识别出记账信息。\n'
              '可以试试「午饭 30」「打车 15」「工资到账 8000」这类说法；'
              '联网后在「我的 → DeepSeek API Key」配置 Key 即可使用完整能力。'
          : '$reason。\n'
              '这句话已排进离线队列，联网后在 AI 页点「重放」会自动补答'
              '（下次成功发消息时也会自动重放）。';

      await aiRepository.addMessage(
        sessionId: sessionId,
        role: 'assistant',
        content: content,
      );
      return AiReply(content: content, usedLocalRules: true);
    }

    final categoryId = await _resolveCategory(parsed.categoryName, parsed.kind);
    await finance.saveTransaction(
      kind: parsed.kind,
      amount: parsed.amount,
      occurredAt: DateTime.now(),
      categoryId: categoryId,
      accountId: defaultAccountId,
      payee: parsed.payee,
      source: TxnSource.ai,
    );

    final content = '已用本地规则记账：'
        '${parsed.kind.label} ¥${formatCents(parsed.amount)}'
        '${parsed.categoryName == null ? '' : ' · ${parsed.categoryName}'}'
        '${parsed.payee == null ? '' : ' · ${parsed.payee}'}\n'
        '（$reason）';

    await aiRepository.addMessage(
      sessionId: sessionId,
      role: 'assistant',
      content: content,
    );
    return AiReply(content: content, usedLocalRules: true);
  }

  Future<String?> _resolveCategory(String? name, TxnKind kind) async {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    final existing = await finance.findCategoryByName(trimmed, kind);
    if (existing != null) return existing.id;

    await finance.saveCategory(name: trimmed, kind: kind);
    final created = await finance.findCategoryByName(trimmed, kind);
    return created?.id;
  }

  Future<String> _systemPrompt() async {
    final name = await assistantName();
    return '你叫「$name」，是朝夕册（LifeLog）里用户的私人生活助手，能直接操作 App 里的全部功能。\n'
        '你的能力：\n'
        '- 财务：记收入/支出（可指定账户、分类、商户、备注、时间）、账户间转账、查日/周/月/年收支与分类占比、'
        '新建账户、查账户余额与总资产、查看分类、设置和查询月度总预算与分类预算。\n'
        '- 健康：记录体重体脂、身体围度（胸围/腰围/臀围等）、运动，查询一段时间的体重/BMI/围度/运动汇总，设置身高。\n'
        '- 学习：查询今日待复习与待学新词数量、最近 30 天学习情况，往词库里添加单词。\n'
        '规则：\n'
        '1. 任何涉及数据的问题都要先调用对应工具，依据真实结果回答，绝不编造数字；需要多个信息时可以连续调用多个工具。\n'
        '2. 用户提到账户时用账户名或银行卡后四位匹配；匹配不到就先 list_accounts，仍然不确定要主动询问，不要乱猜。\n'
        '3. 金额单位元、体重千克、围度和身高厘米；信息不全时省略可选参数即可，不要臆测。\n'
        '4. 记账、转账、建账户、设预算、记健康数据、加单词这类写操作直接执行，不用二次确认，但回复里说清做了什么；'
        '工具返回 ok=false 时，把错误原因用人话告诉用户并给出可行建议。\n'
        '5. 用中文回答，口语化、简洁，一般不超过 3 句话；合适时主动给一句简短建议，像朋友一样自然。\n'
        '6. 当前时间：${formatDateTime(DateTime.now())}';
  }
}
