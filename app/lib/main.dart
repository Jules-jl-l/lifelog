import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/security_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // iOS 卸载后 Keychain 仍在，首次启动时清掉旧 PIN / API Key
  await SecurityStore().clearIfFreshInstall();
  runApp(const ProviderScope(child: LifeLogApp()));
}
