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
/// 系统识别器单次会话很短（Android 静音几秒就会结束），因此这里做连续分段：
/// 一段结束后自动重新开始识别，并把已定稿的分段拼起来，直到用户松手调用
/// [stop]。这样按住说话可以持续任意长的时间，不会出现「说几秒后半段丢失」。
class SpeechToTextInput implements SpeechInput {
  SpeechToTextInput({SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  bool? _ready;
  String? _localeId;

  bool _active = false;
  int _run = 0;

  /// 分段号：用于丢弃上一段迟到的识别结果，避免文字重复。
  int _segment = 0;
  void Function(String text, bool isFinal)? _onResult;

  /// 已定稿的分段文本。
  final _finished = <String>[];

  /// 当前分段的实时识别文本。
  String _partial = '';

  /// 当前分段何时结束（系统给出 final / done 或出错）。
  Completer<void>? _segmentEnd;

  @override
  Future<bool> ensureReady() async {
    final cached = _ready;
    if (cached != null) return cached;

    // 没有系统语音识别服务的设备会直接抛 recognizerNotAvailable
    try {
      _ready = await _speech.initialize(
        onError: (_) => _endSegment(),
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') _endSegment();
        },
      );
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
    if (_active) return true;
    if (!await ensureReady()) return false;

    _onResult = onResult;
    _finished.clear();
    _partial = '';
    _active = true;
    final run = ++_run;

    // 结束信号要在开始监听前建好，避免第一段极快结束被漏掉
    final first = _segmentEnd = Completer<void>();
    final started = await _listenOnce(run);
    if (!started) {
      _active = false;
      return false;
    }
    unawaited(_loop(run, first));
    return true;
  }

  /// 连续识别：一段结束后定稿并自动续接下一段，直到 [stop] 或 [cancel]。
  Future<void> _loop(int run, Completer<void> first) async {
    var end = first;
    while (_active && run == _run) {
      try {
        // 比单段 listenFor 略长，正常情况下由识别器自己结束
        await end.future.timeout(const Duration(seconds: 40));
      } on TimeoutException {
        try {
          await _speech.stop();
        } on Object {
          // 已经结束就忽略
        }
      }

      if (!_active || run != _run) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      _commitSegment();
      if (!_active || run != _run) return;

      end = _segmentEnd = Completer<void>();
      if (!await _listenOnce(run)) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!_active || run != _run) return;
        if (!await _listenOnce(run)) return;
      }
    }
  }

  Future<bool> _listenOnce(int run) async {
    final segment = ++_segment;
    try {
      await _speech.listen(
        onResult: (result) {
          if (run != _run || segment != _segment) return;
          _partial = result.recognizedWords;
          _emit(isFinal: false);
          if (result.finalResult) _endSegment();
        },
        listenOptions: SpeechListenOptions(
          localeId: _localeId,
          partialResults: true,
          // 由本类负责重启，不因单段错误整场取消
          cancelOnError: false,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 6),
        ),
      );
      return true;
    } on Object {
      return false;
    }
  }

  void _endSegment() {
    final end = _segmentEnd;
    if (end != null && !end.isCompleted) end.complete();
  }

  void _commitSegment() {
    final text = _partial.trim();
    if (text.isNotEmpty) _finished.add(text);
    _partial = '';
  }

  void _emit({required bool isFinal}) {
    final text = _joined();
    if (text.isEmpty) return;
    _onResult?.call(text, isFinal);
  }

  /// 拼接分段：中文直接相连，英文单词之间补空格。
  String _joined() {
    final buffer = StringBuffer();
    for (final segment in [..._finished, _partial]) {
      final text = segment.trim();
      if (text.isEmpty) continue;
      if (buffer.isNotEmpty) {
        final previous = buffer.toString();
        if (_asciiWordEnd.hasMatch(previous) &&
            _asciiWordStart.hasMatch(text)) {
          buffer.write(' ');
        }
      }
      buffer.write(text);
    }
    return buffer.toString();
  }

  static final _asciiWordEnd = RegExp(r'[A-Za-z0-9]$');
  static final _asciiWordStart = RegExp(r'^[A-Za-z0-9]');

  @override
  Future<void> stop() async {
    if (!_active) return;
    _active = false;
    final end = _segmentEnd;
    try {
      await _speech.stop();
    } on Object {
      // 识别器可能已自行结束
    }
    if (end != null && !end.isCompleted) {
      await end.future.timeout(
        const Duration(milliseconds: 600),
        onTimeout: () {},
      );
    }
    _commitSegment();
    _emit(isFinal: true);
  }

  @override
  Future<void> cancel() async {
    _active = false;
    _run++;
    _finished.clear();
    _partial = '';
    try {
      await _speech.cancel();
    } on Object {
      // 识别器可能已经停止
    }
  }
}
