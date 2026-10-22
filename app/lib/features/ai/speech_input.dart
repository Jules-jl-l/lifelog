/// 语音输入：界面只依赖 [SpeechInput] 接口，测试可注入假实现。
library;

import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

abstract interface class SpeechInput {
  /// 初始化并申请麦克风权限；设备不支持或用户拒绝时返回 false。
  Future<bool> ensureReady();

  /// 开始识别；[onResult] 会收到中间结果与最终结果。
  Future<bool> start({
    required void Function(String text, bool isFinal) onResult,
  });

  Future<void> stop();

  Future<void> cancel();
}

/// 基于系统语音识别（Android SpeechRecognizer）的实现。
class SpeechToTextInput implements SpeechInput {
  final SpeechToText _speech = SpeechToText();
  bool? _ready;
  String? _localeId;

  @override
  Future<bool> ensureReady() async {
    final cached = _ready;
    if (cached != null) return cached;

    // 没有系统语音识别服务的设备会直接抛 recognizerNotAvailable
    try {
      _ready = await _speech.initialize();
    } on PlatformException {
      _ready = false;
    }

    final ready = _ready ?? false;
    if (ready) {
      try {
        // 优先中文识别，设备没装中文包时退回系统默认语言
        final locales = await _speech.locales();
        for (final locale in locales) {
          if (locale.localeId.toLowerCase().startsWith('zh')) {
            _localeId = locale.localeId;
            break;
          }
        }
      } catch (_) {
        // 取不到语言列表就交给系统默认
      }
    }
    return ready;
  }

  @override
  Future<bool> start({
    required void Function(String text, bool isFinal) onResult,
  }) async {
    if (!await ensureReady()) return false;
    try {
      await _speech.listen(
        onResult: (result) =>
            onResult(result.recognizedWords, result.finalResult),
        listenOptions: SpeechListenOptions(
          localeId: _localeId,
          partialResults: true,
          cancelOnError: true,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 4),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}
