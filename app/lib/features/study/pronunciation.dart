/// 单词发音：调用系统 TTS 引擎，离线可用，不需要下载音频文件。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

class PronunciationService {
  PronunciationService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _configured = false;

  Future<void> _configure() async {
    if (_configured) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1);
    await _tts.setPitch(1);
    _configured = true;
  }

  /// 朗读一个单词；成功返回 null，失败返回可读的错误信息。
  ///
  /// [american] 为 false 时用英式发音（en-GB）。
  Future<String?> speak(String text, {bool american = true}) async {
    try {
      await _configure();
      await _tts.setLanguage(american ? 'en-US' : 'en-GB');
      await _tts.stop();
      await _tts.speak(text);
      return null;
    } on Object catch (error) {
      return '朗读失败：$error（设备可能没有安装 TTS 引擎）';
    }
  }

  Future<void> stop() => _tts.stop();

  Future<void> dispose() => _tts.stop();
}

final pronunciationProvider = Provider<PronunciationService>((ref) {
  final service = PronunciationService();
  ref.onDispose(service.dispose);
  return service;
});

/// 发音按钮；[american] 为 false 时读英式发音。
class PronounceButton extends ConsumerWidget {
  const PronounceButton({
    super.key,
    required this.text,
    this.american = true,
  });

  final String text;
  final bool american;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: american ? '美式发音' : '英式发音',
      icon: Icon(
        american ? Icons.volume_up_outlined : Icons.record_voice_over_outlined,
      ),
      onPressed: () async {
        final error = await ref
            .read(pronunciationProvider)
            .speak(text, american: american);
        if (error != null && context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error)));
        }
      },
    );
  }
}
