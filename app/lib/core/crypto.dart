/// 加密基础设施：PBKDF2 密钥派生、AES-256-GCM 认证加密、安全随机数。
///
/// 纯 Dart 实现（package:cryptography），不依赖平台插件，
/// 因此可以直接在 `flutter test` 里覆盖测试。
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// PIN 的派生次数。
///
/// PIN 只有 4-8 位，真正的防护来自 Android Keystore / iOS Keychain 与校验失败次数限制；
/// 而纯 Dart 的 PBKDF2 要兼顾解锁速度，所以这里取较小值。
const pinKdfIterations = 20000;

/// 备份包的派生次数。备份是低频操作，可以承受几秒耗时，用更强的参数。
const backupKdfIterations = 100000;

/// AES-GCM 认证标签长度（字节）。
const aesGcmTagLength = 16;

class CryptoException implements Exception {
  CryptoException(this.message);

  final String message;

  @override
  String toString() => message;
}

Uint8List randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}

/// PBKDF2-HMAC-SHA256 派生密钥。
Future<Uint8List> deriveKey({
  required String password,
  required Uint8List salt,
  required int iterations,
  int length = 32,
}) async {
  try {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: length * 8,
    );
    final key = await pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  } on CryptoException {
    rethrow;
  } on Object catch (error) {
    throw CryptoException('密钥派生失败：$error');
  }
}

/// AES-256-GCM 加密，返回「密文 + 认证标签」的拼接。
Future<Uint8List> aesGcmSeal({
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List plaintext,
  List<int> aad = const [],
}) async {
  try {
    final box = await AesGcm.with256bits().encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
  } on Object catch (error) {
    throw CryptoException('加密失败：$error');
  }
}

/// AES-256-GCM 解密；认证失败（密码错误或数据被篡改）统一抛 [CryptoException]。
Future<Uint8List> aesGcmOpen({
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List ciphertextWithTag,
  List<int> aad = const [],
}) async {
  if (ciphertextWithTag.length < aesGcmTagLength) {
    throw CryptoException('数据长度不足，无法解密');
  }
  try {
    final box = SecretBox.fromConcatenation(
      <int>[...nonce, ...ciphertextWithTag],
      nonceLength: nonce.length,
      macLength: aesGcmTagLength,
    );
    final clear = await AesGcm.with256bits().decrypt(
      box,
      secretKey: SecretKey(key),
      aad: aad,
    );
    return Uint8List.fromList(clear);
  } on Object catch (_) {
    throw CryptoException('解密失败：密码不正确，或数据已被篡改');
  }
}
