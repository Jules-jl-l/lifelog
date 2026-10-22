/// PIN 与 API Key 的本地安全存储。
///
/// PIN 只保存 PBKDF2 派生出的哈希与盐，明文永不落盘；
/// 存储媒介为 Android Keystore（flutter_secure_storage）。
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/crypto.dart';

const _pinHashKey = 'lifelog.pin';
const _apiKeyKey = 'lifelog.deepseek_key';
const _saltLength = 16;

class SecurityStore {
  SecurityStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// 是否已经设置过 PIN。
  Future<bool> hasPin() async =>
      (await _storage.read(key: _pinHashKey)) != null;

  /// 设置或修改 PIN。
  Future<void> setPin(String pin) async {
    final salt = randomBytes(_saltLength);
    final derived = await deriveKey(
      password: pin,
      salt: salt,
      iterations: pinKdfIterations,
    );
    await _storage.write(
      key: _pinHashKey,
      value: '${base64Encode(salt)}:${base64Encode(derived)}',
    );
  }

  /// 校验 PIN。
  Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _pinHashKey);
    if (stored == null) return false;

    final parts = stored.split(':');
    if (parts.length != 2) return false;

    final salt = base64Decode(parts[0]);
    final expected = base64Decode(parts[1]);
    final actual = await deriveKey(
      password: pin,
      salt: salt,
      iterations: pinKdfIterations,
      length: expected.length,
    );
    return _constantTimeEquals(expected, actual);
  }

  /// 清除 PIN（「修改 PIN」与「重置应用」用）。
  Future<void> clearPin() => _storage.delete(key: _pinHashKey);

  // ------------------------------------------------------------ API Key
  /// 读取 DeepSeek API Key。由使用者在 App 内自行填写，只存本机安全存储，
  /// 既不写进代码也不进入仓库。
  Future<String?> readApiKey() => _storage.read(key: _apiKeyKey);

  Future<void> saveApiKey(String apiKey) =>
      _storage.write(key: _apiKeyKey, value: apiKey.trim());

  Future<void> clearApiKey() => _storage.delete(key: _apiKeyKey);

  /// 常数时间比较，避免通过耗时差异反推哈希。
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
