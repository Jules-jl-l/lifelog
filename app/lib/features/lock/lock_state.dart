/// 解锁状态：驱动 App 在「锁屏」与「主界面」之间切换。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/settings_repository.dart';

/// 是否已解锁（true 表示可以进入主界面）。
class LockController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    // 冷启动默认先锁；若用户在设置里开启了「启动免 PIN」则直接进入。
    final skip = await ref
        .read(settingsRepositoryProvider)
        .get(SettingKeys.skipPinOnStart);
    return skip == '1';
  }

  void unlock() => state = const AsyncValue.data(true);

  void lock() => state = const AsyncValue.data(false);
}

final lockStatusProvider =
    AsyncNotifierProvider<LockController, bool>(LockController.new);

/// 是否启用「启动免 PIN」。
final skipPinOnStartProvider = FutureProvider<bool>((ref) async {
  final value = await ref
      .watch(settingsRepositoryProvider)
      .get(SettingKeys.skipPinOnStart);
  return value == '1';
});

/// 是否已经设置过 PIN。
final hasPinProvider = FutureProvider<bool>(
  (ref) => ref.watch(securityStoreProvider).hasPin(),
);

/// 离开超过该时长后回到前台需要重新解锁。
const relockAfter = Duration(minutes: 5);
