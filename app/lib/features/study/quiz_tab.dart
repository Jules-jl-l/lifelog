/// 测验页：选择词库 / 模式 / 题量，进入拼写或听写。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_x.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import '../../data/study/quiz.dart';
import '../../data/study_stats.dart';
import 'pronunciation.dart';
import 'study_providers.dart';

class QuizTab extends ConsumerStatefulWidget {
  const QuizTab({super.key});

  @override
  ConsumerState<QuizTab> createState() => _QuizTabState();
}

class _QuizTabState extends ConsumerState<QuizTab> {
  String? _wordbookId;
  QuizMode _mode = QuizMode.meaning;
  int _requested = 10;
  bool? _ttsAvailable;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _probeTts();
  }

  Future<void> _probeTts() async {
    final available = await ref.read(pronunciationProvider).isAvailable();
    if (mounted) setState(() => _ttsAvailable = available);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final books = ref.watch(wordbooksProvider).dataOrNull ?? const <Wordbook>[];
    final selected = books.where((book) => book.id == _wordbookId).firstOrNull ??
        (books.isEmpty ? null : books.first);
    final words = selected == null
        ? const <WordEntry>[]
        : ref.watch(wordsProvider(selected.id)).dataOrNull ??
            const <WordEntry>[];
    final recent =
        ref.watch(recentQuizSessionsProvider).dataOrNull ?? const <QuizSessionEntry>[];
    final dictationAvailable = _ttsAvailable ?? true;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.spellcheck, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('拼写测验', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '选词库、模式和题量，完成后计入测验战绩，不影响背词进度。',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selected?.id,
                  decoration: const InputDecoration(labelText: '词库'),
                  items: [
                    for (final book in books)
                      DropdownMenuItem(
                        value: book.id,
                        child: Text('${book.name}（${book.wordCount} 词）'),
                      ),
                  ],
                  onChanged: (value) => setState(() => _wordbookId = value),
                ),
                const SizedBox(height: 16),
                Text('模式', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<QuizMode>(
                  segments: [
                    for (final mode in QuizMode.values)
                      ButtonSegment(
                        value: mode,
                        label: Text(mode.label),
                        enabled:
                            mode != QuizMode.dictation || dictationAvailable,
                      ),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (values) =>
                      setState(() => _mode = values.first),
                ),
                const SizedBox(height: 6),
                Text(
                  _mode.description,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                if (!dictationAvailable) ...[
                  const SizedBox(height: 6),
                  Text(
                    '当前设备没有可用的语音引擎，听写模式已禁用。',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                Text('题量', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 10, label: Text('10 题')),
                    ButtonSegment(value: 20, label: Text('20 题')),
                    ButtonSegment(value: 0, label: Text('全部')),
                  ],
                  selected: {_requested},
                  showSelectedIcon: false,
                  onSelectionChanged: (values) =>
                      setState(() => _requested = values.first),
                ),
                const SizedBox(height: 6),
                Text(
                  selected == null
                      ? '还没有词库，请稍候或到「词库」新建'
                      : '当前词库含 ${words.length} 个词 · 单轮最多 $maxQuizQuestions 题',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: selected == null ||
                          words.isEmpty ||
                          _starting
                      ? null
                      : () => _start(selected, words),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始测验'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text('最近成绩', style: theme.textTheme.titleSmall),
            const Spacer(),
            if (recent.isNotEmpty)
              Text(
                '共 ${recent.length} 次',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '还没有测验记录。完成一轮后会显示正确率与用时。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final session in recent)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      session.mode == QuizMode.dictation
                          ? Icons.headphones_outlined
                          : Icons.translate,
                    ),
                    title: Text(
                      '${session.mode.label} · ${session.total} 题',
                    ),
                    subtitle: Text(formatDateTime(session.createdAt)),
                    trailing: Text(
                      '${(session.accuracy * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _start(Wordbook book, List<WordEntry> words) async {
    final questions = pickQuizQuestions(
      words: words,
      mode: _mode,
      count: _requested,
    );
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _mode == QuizMode.meaning
                ? '这个词库缺少释义，暂时无法进行看释义拼写'
                : '这个词库还没有可用于测验的单词',
          ),
        ),
      );
      return;
    }

    setState(() => _starting = true);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuizSessionPage(
          questions: questions,
          mode: _mode,
          wordbookId: book.id,
          wordbookName: book.name,
        ),
      ),
    );
    if (mounted) setState(() => _starting = false);
  }
}

class _WrongAnswer {
  const _WrongAnswer({required this.question, required this.answer});

  final QuizQuestion question;
  final String answer;
}

class QuizSessionPage extends ConsumerStatefulWidget {
  const QuizSessionPage({
    super.key,
    required this.questions,
    required this.mode,
    this.wordbookId,
    this.wordbookName,
  });

  final List<QuizQuestion> questions;
  final QuizMode mode;
  final String? wordbookId;
  final String? wordbookName;

  @override
  ConsumerState<QuizSessionPage> createState() => _QuizSessionPageState();
}

class _QuizSessionPageState extends ConsumerState<QuizSessionPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _answers = <QuizAnswerDraft>[];
  final _wrong = <_WrongAnswer>[];
  late final DateTime _startedAt = DateTime.now();
  late final PronunciationService _tts;

  int _index = 0;
  bool? _feedback;
  String? _hint;
  String? _ttsError;
  bool _meaningFallback = false;
  bool _finished = false;
  bool _saving = false;
  bool _allowPop = false;

  QuizQuestion get _current => widget.questions[_index];
  bool get _isLast => _index >= widget.questions.length - 1;
  int get _correct => _answers.where((answer) => answer.correct).length;

  @override
  void initState() {
    super.initState();
    _tts = ref.read(pronunciationProvider);
    if (widget.mode == QuizMode.dictation) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _speak());
    }
  }

  @override
  void dispose() {
    unawaited(_tts.stop());
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _speak() async {
    final error = await _tts.speak(_current.word.spelling);
    if (!mounted) return;
    setState(() => _ttsError = error);
  }

  void _submit() {
    final input = _controller.text;
    if (normalizeSpelling(input).isEmpty) {
      setState(() => _hint = '请输入拼写');
      return;
    }
    _tts.stop();
    final correct = isSpellingCorrect(input, _current.word.spelling);
    _answers.add(
      QuizAnswerDraft(
        wordId: _current.word.id,
        answer: input.trim(),
        correct: correct,
        answeredAt: DateTime.now(),
      ),
    );
    if (!correct) {
      _wrong.add(_WrongAnswer(question: _current, answer: input.trim()));
    }
    setState(() {
      _feedback = correct;
      _hint = null;
    });
  }

  void _revealAnswer() {
    _tts.stop();
    _answers.add(
      QuizAnswerDraft(
        wordId: _current.word.id,
        answer: '',
        correct: false,
        answeredAt: DateTime.now(),
      ),
    );
    _wrong.add(_WrongAnswer(question: _current, answer: ''));
    setState(() => _feedback = false);
  }

  Future<void> _next() async {
    if (_isLast) {
      await _finish();
      return;
    }
    setState(() {
      _index++;
      _feedback = null;
      _hint = null;
      _ttsError = null;
      _controller.clear();
    });
    _focus.requestFocus();
    if (widget.mode == QuizMode.dictation && !_meaningFallback) {
      await _speak();
    }
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(studyRepositoryProvider).saveQuizResult(
            wordbookId: widget.wordbookId,
            mode: widget.mode,
            answers: _answers,
            durationSec: DateTime.now().difference(_startedAt).inSeconds,
          );
      if (!mounted) return;
      setState(() {
        _finished = true;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存成绩失败：$error')));
    }
  }

  Future<void> _confirmExit() async {
    if (_answers.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出测验？'),
        content: const Text('本轮尚未完成，退出后不会保存成绩。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续答题'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      setState(() => _allowPop = true);
      await Future<void>.delayed(Duration.zero);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return _buildSummary(context);

    final theme = Theme.of(context);
    final question = _current;
    final answered = _feedback != null;
    final showMeaning = question.mode == QuizMode.meaning || _meaningFallback;

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '拼写测验  ${_index + 1} / ${widget.questions.length}',
          ),
          actions: [
            TextButton(
              onPressed: _confirmExit,
              child: const Text('结束'),
            ),
          ],
        ),
        body: Column(
          children: [
            LinearProgressIndicator(
              value: (_index + 1) / widget.questions.length,
              minHeight: 4,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.wordbookName != null)
                      Text(
                        widget.wordbookName!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    const SizedBox(height: 8),
                    if (showMeaning)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('根据释义写出单词',
                                  style: theme.textTheme.labelLarge),
                              const SizedBox(height: 8),
                              for (final meaning in question.word.meanings)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    meaning,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                    else
                      Center(
                        child: Column(
                          children: [
                            IconButton.filledTonal(
                              iconSize: 48,
                              onPressed: _speak,
                              icon: const Icon(Icons.volume_up),
                            ),
                            const SizedBox(height: 8),
                            Text('听发音，写出单词',
                                style: theme.textTheme.labelLarge),
                            const SizedBox(height: 4),
                            Text('可以点喇叭再听一次',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                )),
                          ],
                        ),
                      ),
                    if (_ttsError != null && !showMeaning) ...[
                      const SizedBox(height: 12),
                      Card(
                        color: theme.colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Text(
                                '无法播放发音：$_ttsError',
                                style: TextStyle(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    setState(() => _meaningFallback = true),
                                child: const Text('改用释义拼写'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: true,
                      enabled: !answered,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => answered ? _next() : _submit(),
                      onChanged: (_) {
                        if (_hint != null) setState(() => _hint = null);
                      },
                      decoration: InputDecoration(
                        labelText: '英文拼写',
                        hintText: '输入后按回车提交',
                        errorText: _hint,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (answered)
                      Card(
                        color: _feedback == true
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _feedback == true
                                    ? '拼写正确'
                                    : '正确答案：${question.word.spelling}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: _feedback == true
                                      ? theme.colorScheme.onPrimaryContainer
                                      : theme.colorScheme.onErrorContainer,
                                ),
                              ),
                              if (question.word.meanings.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  question.word.meanings.join('；'),
                                  style: TextStyle(
                                    color: _feedback == true
                                        ? theme.colorScheme.onPrimaryContainer
                                        : theme.colorScheme.onErrorContainer,
                                  ),
                                ),
                              ],
                              if (question.word.phoneticUk != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  question.word.phoneticUk!,
                                  style: TextStyle(
                                    color: _feedback == true
                                        ? theme.colorScheme.onPrimaryContainer
                                        : theme.colorScheme.onErrorContainer,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: answered
                    ? FilledButton(
                        onPressed: _saving ? null : _next,
                        child: Text(_saving
                            ? '正在保存…'
                            : _isLast
                                ? '查看结果'
                                : '下一题'),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _revealAnswer,
                              child: const Text('不会'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: _submit,
                              child: const Text('提交'),
                            ),
                          ),
                        ],
                      ),
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
    final rate = _answers.isEmpty ? 0.0 : _correct / _answers.length;

    return Scaffold(
      appBar: AppBar(title: const Text('本轮结果')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          Icon(
            Icons.emoji_events_outlined,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            '本轮 ${_answers.length} 题 · 正确 $_correct 题',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            '正确率 ${(rate * 100).toStringAsFixed(0)}% · '
            '用时 ${formatStudyDuration(seconds)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 24),
          if (_wrong.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '全部答对，继续保持。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            )
          else ...[
            Text('错题 ${_wrong.length} 个', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final wrong in _wrong)
              Card(
                child: ListTile(
                  title: Text(wrong.question.word.spelling),
                  subtitle: Text(
                    '你的答案：${wrong.answer.isEmpty ? '未作答' : wrong.answer}'
                    '${wrong.question.word.meanings.isEmpty ? '' : '\n${wrong.question.word.meanings.join('；')}'}',
                  ),
                ),
              ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }
}
