import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/security_store.dart';
import 'data/spaces/space_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // iOS 卸载后 Keychain 仍在，首次启动时清掉旧 PIN / API Key
  await SecurityStore().clearIfFreshInstall();

  // 先读出数据空间清单，避免启动后再异步切换数据库造成首屏闪烁
  final spaces = await SpaceStore().load();

  runApp(
    ProviderScope(
      overrides: [
        initialSpaceSnapshotProvider.overrideWithValue(spaces),
      ],
      child: const LifeLogApp(),
    ),
  );
}
