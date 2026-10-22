/// 背词会话：逐张卡片展示，三档反馈（认识 / 模糊 / 不认识）驱动 SRS 排程。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/study_stats.dart';
import 'pronunciation.dart';

class ReviewSessionPage extends ConsumerStatefulWidget {
  const ReviewSessionPage({super.key, required this.queue});

  /// 本次要过一遍的卡片（调用方传入快照）。
  final List<CardState> queue;

  @override
  ConsumerState<ReviewSessionPage> createState() => _ReviewSessionPageState();
}

class _ReviewSessionPageState extends ConsumerState<ReviewSessionPage> {
  late final List<CardState> _queue = [...widget.queue];
  late final DateTime _startedAt = DateTime.now();

  int _index = 0;
  bool _revealed = false;
  bool _busy = false;
  int _answered = 0;
  int _correct = 0;

  CardState? get _current => _index < _queue.length ? _queue[_index] : null;

  bool get _finished => _answered > 0 && _current == null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_finished) return _buildSummary(context);

    final card = _current;
    if (card == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('背词')),
        body: const Center(child: Text('没有需要复习的词')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('背词  ${_index + 1} / ${_queue.length}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('结束'),
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: _queue.isEmpty ? 0 : (_index + 1) / _queue.length,
            minHeight: 4,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (card.isNew)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Chip(
                        label: const Text('新词'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    card.word.spelling,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PronounceButton(text: card.word.spelling),
                      if (card.word.phoneticUs != null &&
                          card.word.phoneticUs != card.word.phoneticUk)
                        PronounceButton(
                          text: card.word.spelling,
                          american: false,
                        ),
                    ],
                  ),
                  if (card.word.phoneticUk != null ||
                      card.word.phoneticUs != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      [
                        if (card.word.phoneticUk != null) card.word.phoneticUk,
                        if (card.word.phoneticUs != null &&
                            card.word.phoneticUs != card.word.phoneticUk)
                          card.word.phoneticUs,
                      ].join('   '),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                  const SizedBox(height: 32),
                  if (_revealed) ...[
                    for (final meaning in card.word.meanings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(meaning, style: theme.textTheme.titleMedium),
                      ),
                    if (card.word.examples.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      for (final example in card.word.examples)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            example,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                    ],
                  ] else
                    Center(
                      child: TextButton(
                        onPressed: () => setState(() => _revealed = true),
                        child: const Text('显示释义'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_revealed) _buildActions(context, card),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, CardState card) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: _busy
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              )
            : Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _answer(ReviewResult.unknown),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      child: const Text('不认识'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _answer(ReviewResult.vague),
                      child: const Text('模糊'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _answer(ReviewResult.know),
                      child: const Text('认识'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final theme = Theme.of(context);
    final seconds = DateTime.now().difference(_startedAt).inSeconds;
    final rate = _answered == 0 ? 0.0 : _correct / _answered;

    return Scaffold(
      appBar: AppBar(title: const Text('本轮结果')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.emoji_events_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                '本轮过了 $_answered 张卡',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '认识 $_correct · 正确率 ${(rate * 100).toStringAsFixed(0)}% · '
                '用时 ${formatStudyDuration(seconds)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _answer(ReviewResult result) async {
    if (_busy) return;
    final card = _current;
    if (card == null) return;

    setState(() => _busy = true);

    final now = DateTime.now();
    final outcome = scheduleReview(
      result: result,
      repetitions: card.repetitions,
      ease: card.ease,
      intervalDays: card.intervalDays,
      now: now,
    );

    try {
      await ref.read(studyRepositoryProvider).recordReview(
            wordId: card.word.id,
            result: result,
            outcome: outcome,
            isNewWord: card.isNew,
          );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      return;
    }

    if (!mounted) return;
    setState(() {
      _answered++;
      if (result.isCorrect) _correct++;
      // 不认识的词本轮再过一遍
      if (result == ReviewResult.unknown) {
        _queue.add(
          CardState(
            word: card.word,
            repetitions: outcome.repetitions,
            ease: outcome.ease,
            intervalDays: outcome.intervalDays,
            nextReviewAt: outcome.nextReviewAt,
          ),
        );
      }
      _index++;
      _revealed = false;
      _busy = false;
    });

    if (_current == null) {
      final seconds = DateTime.now().difference(_startedAt).inSeconds;
      await ref
          .read(studyRepositoryProvider)
          .bumpDailyStat(durationSec: seconds);
    }
  }
}
