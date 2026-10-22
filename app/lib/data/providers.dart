/// Riverpod 依赖注入：数据库、仓库、安全存储都是全局单例。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import 'backup/backup_service.dart';
import 'biometric_service.dart';
import 'db/database.dart';
import 'export/csv_export.dart';
import 'finance_repository.dart';
import 'health_repository.dart';
import 'recycle_bin_repository.dart';
import 'security_store.dart';
import 'settings_repository.dart';
import 'study/builtin_wordbooks.dart';
import 'study_repository.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final financeRepositoryProvider = Provider<FinanceRepository>(
  (ref) => FinanceRepository(ref.watch(databaseProvider)),
);

final healthRepositoryProvider = Provider<HealthRepository>(
  (ref) => HealthRepository(ref.watch(databaseProvider)),
);

final studyRepositoryProvider = Provider<StudyRepository>(
  (ref) => StudyRepository(ref.watch(databaseProvider)),
);

/// 内置词库资源；测试可覆盖为小型固定数据，避免每次播种上万行。
final builtinWordbooksProvider = FutureProvider<List<BuiltinWordbookData>>(
  (ref) => loadBuiltinWordbooks(),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

final securityStoreProvider = Provider<SecurityStore>((ref) => SecurityStore());

/// 指纹 / 面容解锁（测试可覆盖为假实现）。
final biometricServiceProvider = Provider<BiometricService>(
  (ref) => LocalBiometricService(),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(databaseProvider)),
);

final recycleBinRepositoryProvider = Provider<RecycleBinRepository>(
  (ref) => RecycleBinRepository(ref.watch(databaseProvider)),
);

final exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(ref.watch(databaseProvider)),
);

/// 上次备份时间（用于「距上次备份已过 N 天」提醒）。
final lastBackupAtProvider = StreamProvider<DateTime?>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watch(SettingKeys.lastBackupAt)
      .map((value) => value == null ? null : DateTime.tryParse(value)),
);

/// 当前主题色：跟随设置变化，未设置时为默认「晨绿」。
final themeAccentProvider = StreamProvider<ThemeAccent>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watch(SettingKeys.themeAccent)
      .map(themeAccentFrom),
);
