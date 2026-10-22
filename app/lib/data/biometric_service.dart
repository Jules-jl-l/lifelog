/// 指纹 / 面容解锁封装。
///
/// 通过接口隔离 local_auth，便于 Widget 测试注入假实现。
library;

import 'package:local_auth/local_auth.dart';

abstract interface class BiometricService {
  /// 设备是否有可用的、已录入的生物识别。
  Future<bool> isAvailable();

  /// 拉起系统生物识别弹窗，返回是否验证通过。
  Future<bool> authenticate({required String reason});
}

class LocalBiometricService implements BiometricService {
  LocalBiometricService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.canCheckBiometrics) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on Object {
      return false;
    }
  }
}
