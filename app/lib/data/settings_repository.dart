/// 应用设置的键值读写。
library;

import 'db/database.dart';

/// 设置项的键名集中在这里，避免散落的字符串字面量。
abstract final class SettingKeys {
  static const themeMode = 'theme_mode';
  static const lastBackupAt = 'last_backup_at';
  static const defaultAccountId = 'default_account_id';
  static const deepseekApiKey = 'deepseek_api_key';
  static const deepseekModel = 'deepseek_model';
  static const heightCm = 'height_cm';

  /// 用户给 AI 助手起的名字；未设置时用默认名「小朝」。
  static const assistantName = 'assistant_name';

  /// 主题色（ThemeAccent 的名字）；未设置时用默认「晨绿」。
  static const themeAccent = 'theme_accent';

  /// 启动时跳过 PIN 锁屏（'1' 开启 / '0' 关闭）。
  static const skipPinOnStart = 'skip_pin_on_start';
}

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Future<String?> get(String key) async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  Future<void> remove(String key) async {
    await (_db.delete(_db.appSettings)..where((t) => t.key.equals(key))).go();
  }

  Stream<String?> watch(String key) => (_db.select(_db.appSettings)
        ..where((t) => t.key.equals(key)))
      .watchSingleOrNull()
      .map((row) => row?.value);
}
