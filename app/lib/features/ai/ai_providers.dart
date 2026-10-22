/// AI 模块的 Riverpod Provider。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ai/ai_queue_worker.dart';
import '../../data/ai/ai_service.dart';
import '../../data/ai/deepseek_client.dart';
import '../../data/ai_repository.dart';
import '../../data/ai_pending_repository.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import '../../data/settings_repository.dart';
import 'speech_input.dart';

export '../../data/ai/ai_service.dart' show defaultAssistantName;

final deepSeekClientProvider = Provider<DeepSeekClient>(
  (ref) => DeepSeekClient(),
);

/// 语音输入实现；测试里覆盖成假实现即可不碰平台通道。
final speechInputProvider = Provider<SpeechInput>(
  (ref) => SpeechToTextInput(),
);

final aiRepositoryProvider = Provider<AiRepository>(
  (ref) => AiRepository(ref.watch(databaseProvider)),
);

final aiPendingRepositoryProvider = Provider<AiPendingRepository>(
  (ref) => AiPendingRepository(ref.watch(databaseProvider)),
);

final aiServiceProvider = Provider<AiService>(
  (ref) => AiService(
    client: ref.watch(deepSeekClientProvider),
    aiRepository: ref.watch(aiRepositoryProvider),
    pending: ref.watch(aiPendingRepositoryProvider),
    finance: ref.watch(financeRepositoryProvider),
    health: ref.watch(healthRepositoryProvider),
    study: ref.watch(studyRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    security: ref.watch(securityStoreProvider),
  ),
);

/// 助手当前名字：跟随设置变化，未设置时为默认名「小朝」。
final assistantNameProvider = StreamProvider<String>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watch(SettingKeys.assistantName)
      .map((value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty)
        ? defaultAssistantName
        : trimmed;
  }),
);

final aiQueueWorkerProvider = Provider<AiQueueWorker>(
  (ref) => AiQueueWorker(
    pending: ref.watch(aiPendingRepositoryProvider),
    ai: ref.watch(aiServiceProvider),
    client: ref.watch(deepSeekClientProvider),
    security: ref.watch(securityStoreProvider),
  ),
);

/// 还需要处理的任务（待联网 / 待确认 / 失败）。
final pendingTasksProvider = StreamProvider<List<PendingTask>>(
  (ref) => ref.watch(aiPendingRepositoryProvider).watchOpen(),
);

final chatSessionsProvider = StreamProvider<List<ChatSession>>(
  (ref) => ref.watch(aiRepositoryProvider).watchSessions(),
);

final chatMessagesProvider =
    StreamProvider.family<List<ChatMessage>, String>(
  (ref, sessionId) =>
      ref.watch(aiRepositoryProvider).watchMessages(sessionId),
);

/// 是否已经配置过 DeepSeek API Key。
final apiKeyConfiguredProvider = FutureProvider<bool>((ref) async {
  final key = await ref.watch(securityStoreProvider).readApiKey();
  return key != null && key.isNotEmpty;
});
