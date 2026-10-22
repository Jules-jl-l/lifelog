/// 应用根组件：根据解锁状态在锁屏与主界面之间切换，并处理超时重新锁屏。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/async_x.dart';
import 'core/theme.dart';
import 'data/providers.dart';
import 'features/home/home_shell.dart';
import 'features/lock/lock_page.dart';
import 'features/lock/lock_state.dart';

class LifeLogApp extends ConsumerStatefulWidget {
  const LifeLogApp({super.key});

  @override
  ConsumerState<LifeLogApp> createState() => _LifeLogAppState();
}

class _LifeLogAppState extends ConsumerState<LifeLogApp>
    with WidgetsBindingObserver {
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null &&
            DateTime.now().difference(since) >= relockAfter) {
          _relockIfNeeded();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// 开启了「启动免 PIN」时，后台超时也不回锁屏；手动「立即锁定」仍然生效。
  Future<void> _relockIfNeeded() async {
    final skip = await ref.read(skipPinOnStartProvider.future);
    if (!skip) {
      ref.read(lockStatusProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(lockStatusProvider);
    final accent = ref.watch(themeAccentProvider).dataOrNull ?? ThemeAccent.green;

    return MaterialApp(
      title: '朝夕册',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light, seed: accent.seed),
      darkTheme: buildAppTheme(Brightness.dark, seed: accent.seed),
      home: status.when(
        loading: () => const _Splash(),
        error: (error, _) => _Splash(message: '$error'),
        data: (unlocked) => unlocked ? const HomeShell() : const LockPage(),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(message!),
            ],
          ],
        ),
      ),
    );
  }
}
