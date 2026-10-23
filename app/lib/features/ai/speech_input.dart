/// 语音输入：界面只依赖 [SpeechInput] 接口，测试可注入假实现。
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

abstract interface class SpeechInput {
  /// 初始化并申请麦克风权限；设备不支持或用户拒绝时返回 false。
  Future<bool> ensureReady();

  /// 开始识别；[onResult] 会收到中间结果与最终结果。
  Future<bool> start({
    required void Function(String text, bool isFinal) onResult,
  });

  /// 结束识别；返回前会把最后一段识别结果通过 [onResult] 定稿。
  Future<void> stop();

  Future<void> cancel();
}

/// 基于系统语音识别的实现（Android SpeechRecognizer / iOS Speech）。
///
/// 只维持**一次** listen 会话：
/// Android 的识别器在一次会话结束后不能可靠地快速重启（cancel → listen 会卡在
/// busy，后续段静默失败），所以不做分段续接。通过把 pauseFor 放大到 30 秒，
/// 让正常说话中的短暂停顿不会结束会话；listenFor 60 秒覆盖大多数一次输入。
class SpeechToTextInput implements SpeechInput {
  SpeechToTextInput({SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  bool? _ready;
  String? _localeId;
  String _recognized = '';
  void Function(String text, bool isFinal)? _onResult;

  /// 最终结果是否已经到达：用户松手后要等它，否则会读到空文本。
  Completer<void>? _finalSeen;

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

    _onResult = onResult;
    _recognized = '';
    _finalSeen = Completer<void>();
    try {
      await _speech.listen(
        onResult: (result) {
          _recognized = result.recognizedWords;
          if (result.finalResult) {
            final done = _finalSeen;
            if (done != null && !done.isCompleted) done.complete();
          }
          _onResult?.call(_recognized, result.finalResult);
        },
        listenOptions: SpeechListenOptions(
          localeId: _localeId,
          partialResults: true,
          // 单次会话里遇到瞬时错误不要整场取消，避免还没听到内容就结束
          cancelOnError: false,
          listenFor: const Duration(seconds: 60),
          // 说话中的短暂停顿不应结束会话（部分机型系统仍会提前收尾）
          pauseFor: const Duration(seconds: 8),
        ),
      );
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    final waitFinal = _finalSeen;
    try {
      await _speech.stop();
    } on Object {
      // 识别器可能已自行结束
    }
    // stop() 只代表「停止指令已下发」，最终结果是异步回来的：
    // 等最多 1.5 秒，避免用户松手时读到空文本。
    if (waitFinal != null && !waitFinal.isCompleted) {
      await waitFinal.future.timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () {},
      );
    }
    if (_recognized.isNotEmpty) _onResult?.call(_recognized, true);
  }

  @override
  Future<void> cancel() async {
    _recognized = '';
    _finalSeen = null;
    try {
      await _speech.cancel();
    } on Object {
      // 识别器可能已经停止
    }
  }
}
