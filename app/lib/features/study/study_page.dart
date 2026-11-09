/// 学习模块：学习时间统计（主页面）+ 英语学习子模块。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_x.dart';
import '../../core/period.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import '../../data/study/quiz.dart';
import '../../data/study_stats.dart';
import '../../shared/line_trend_chart.dart';
import '../../shared/period_strip.dart';
import '../../shared/stat_card.dart';
import 'pronunciation.dart';
import 'quiz_tab.dart';
import 'review_session.dart';
import 'study_providers.dart';
import 'word_import_sheet.dart';

class StudyPage extends ConsumerStatefulWidget {
  const StudyPage({super.key});

  @override
  ConsumerState<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends ConsumerState<StudyPage> {
  ViewPeriod _period = ViewPeriod.month;
  late final DateTime _bootAt;
  late DateTime _anchor;
  late DateTime _now;
  Timer? _ticker;
  bool _timerBusy = false;

  @override
  void initState() {
    super.initState();
    _bootAt = DateTime.now();
    _anchor = _bootAt;
    _now = _bootAt;

    // 首次进入时写入内置词库（幂等，已存在则跳过）
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final books = await ref.read(builtinWordbooksProvider.future);
        await ref
            .read(studyRepositoryProvider)
            .ensureBuiltinWordbooks(books: books);
      } on Object {
        // 资源加载失败时不阻塞页面，用户仍可使用自建词库
      }
    });
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }

  void _startTicker() {
    if (_ticker != null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  ViewPeriod get _rangePeriod => _period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (start, end) = _rangePeriod.rangeOf(_anchor);
    final options = periodOptions(_rangePeriod, _now);
    final selectedKey = _selectedPeriodKey(options);
    final sessionsAsync =
        ref.watch(studySessionsProvider((start: start, end: end)));
    final sessions = sessionsAsync.dataOrNull ?? const <StudySessionEntry>[];
    final running = ref.watch(runningStudySessionProvider).dataOrNull;

    // 只有计时进行中才按秒刷新，避免空闲时整页每秒重建
    if (running != null) {
      if (_ticker == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startTicker();
        });
      }
    } else {
      _stopTicker();
    }

    final summary = summarizeStudyTime(sessions, now: _now);
    final average = studyTimeAverageSec(
      totalSec: summary.totalSec,
      period: _rangePeriod,
      anchor: _anchor,
      now: _now,
    );
    final todaySec = sessions
        .where(
          (session) =>
              formatDate(session.startedAt) == formatDate(_now),
        )
        .fold<int>(
          0,
          (sum, session) => sum + session.effectiveDurationSec(_now),
        );
    final points = studyTimeTrend(
      sessions,
      _rangePeriod,
      _anchor,
      now: _now,
    );
    final runningSeconds = running?.effectiveDurationSec(_now) ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('学习')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SegmentedButton<ViewPeriod>(
            segments: [
              for (final period in ViewPeriod.values)
                ButtonSegment(value: period, label: Text(period.label)),
            ],
            selected: {_rangePeriod},
            showSelectedIcon: false,
            onSelectionChanged: (values) =>
                setState(() => _period = values.first),
          ),
          const SizedBox(height: 4),
          PeriodStrip(
            options: options,
            selectedKey: selectedKey,
            onSelected: (option) => setState(() => _anchor = option.anchor),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              periodRangeHint(_rangePeriod, start, end),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text('学习计时', style: theme.textTheme.titleMedium),
                      const Spacer(),
                      if (running != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer
                                .withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '进行中',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.primary),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatStudyTimer(runningSeconds),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 30,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _timerBusy || running != null
                              ? null
                              : _startStudy,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('开始学习'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _timerBusy || running == null
                              ? null
                              : _stopStudy,
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('结束学习'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    running == null
                        ? '点击开始，自动记录学习时长；计时记录不支持手动修改'
                        : '开始于 ${formatDateTime(running.startedAt)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: '学习总时长',
                  value: summary.count == 0
                      ? '—'
                      : formatStudyTotal(summary.totalSec),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: _rangePeriod == ViewPeriod.year ? '月均' : '日均',
                  value: summary.count == 0
                      ? '—'
                      : formatStudyTotal(average),
                  hint: _rangePeriod == ViewPeriod.year ? '按已过月数' : '按已过天数',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: '学习次数',
                  value: '${summary.count} 次',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: '今日学习',
                  value: todaySec == 0 ? '—' : formatStudyTotal(todaySec),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('学习时长趋势', style: theme.textTheme.titleMedium),
                      const Spacer(),
                      Text(
                        _rangePeriod == ViewPeriod.year ? '按月 · 分钟' : '按天 · 分钟',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LineTrendChart(
                    points: points,
                    decimals: 0,
                    tooltipValueFormatter: (value) =>
                        '${value.toStringAsFixed(0)} 分钟',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                for (final session in sessions.reversed.take(30))
                  ListTile(
                    title: Text(
                      '${formatStudyTotal(session.effectiveDurationSec(_now))}'
                      '${session.isRunning ? ' · 进行中' : ''}',
                    ),
                    subtitle: Text(
                      '${formatDateTime(session.startedAt)}'
                      '${session.endedAt == null ? '' : ' ~ ${formatDateTime(session.endedAt!)}'}',
                    ),
                  ),
                if (sessions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('该区间还没有学习记录'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Text('英语学习', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  '可继续拓展其他学习模块',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: const Text('背词'),
                  subtitle: const Text('按 SRS 复习今日队列'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openEnglishModule(
                    const _EnglishModulePage(
                      title: '英语学习 · 背词',
                      child: _ReviewTab(),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.spellcheck),
                  title: const Text('测验'),
                  subtitle: const Text('看释义拼写 / 听音拼写'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openEnglishModule(
                    const _EnglishModulePage(
                      title: '英语学习 · 测验',
                      child: QuizTab(),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.library_books_outlined),
                  title: const Text('词库'),
                  subtitle: const Text('内置词库、自建词库与导入'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openEnglishModule(
                    const _EnglishModulePage(
                      title: '英语学习 · 词库',
                      child: _WordbooksTab(),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.insights_outlined),
                  title: const Text('学习统计'),
                  subtitle: const Text('词量、正确率、用时与测验战绩'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openEnglishModule(
                    const _EnglishModulePage(
                      title: '英语学习 · 统计',
                      child: _StatsTab(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _selectedPeriodKey(List<PeriodOption> options) {
    for (final option in options.reversed) {
      final (start, end) = _rangePeriod.rangeOf(option.anchor);
      if (!_anchor.isBefore(start) && !_anchor.isAfter(end)) {
        return option.key;
      }
    }
    return options.last.key;
  }

  void _openEnglishModule(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _startStudy() async {
    setState(() => _timerBusy = true);
    try {
      await ref.read(studyRepositoryProvider).startStudySession();
      if (mounted) setState(() => _now = DateTime.now());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('开始计时失败：$error')));
    } finally {
      if (mounted) setState(() => _timerBusy = false);
    }
  }

  Future<void> _stopStudy() async {
    final running = ref.read(runningStudySessionProvider).dataOrNull;
    if (running == null) return;
    setState(() => _timerBusy = true);
    try {
      await ref
          .read(studyRepositoryProvider)
          .stopStudySession(id: running.id);
      if (!mounted) return;
      final seconds = running.effectiveDurationSec(DateTime.now());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已记录学习 ${formatStudyTotal(seconds)}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('结束计时失败：$error')));
    } finally {
      if (mounted) setState(() => _timerBusy = false);
    }
  }
}

/// 英语学习子模块的独立页面容器。
class _EnglishModulePage extends StatelessWidget {
  const _EnglishModulePage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    );
  }
}

// ------------------------------------------------------------ 背词

class _ReviewTab extends ConsumerWidget {
  const _ReviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final queue = ref.watch(dailyQueueProvider);
    final stats = ref
            .watch(studyStatsProvider((start: now, end: now)))
            .dataOrNull ??
        const <StudyStatEntry>[];
    final today = stats.isEmpty
        ? const StudyStatEntry(statDate: '')
        : stats.first;

    final dueCount = queue.where((card) => !card.isNew).length;
    final newCount = queue.where((card) => card.isNew).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(label: '今日已学', value: '${today.total} 词'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: '正确率',
                value: today.total == 0
                    ? '—'
                    : '${(today.correctRate * 100).toStringAsFixed(0)}%',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: '今日用时',
                value: today.durationSec == 0
                    ? '—'
                    : formatStudyDuration(today.durationSec),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: '待复习',
                value: '$dueCount 词',
                hint: '新词 $newCount',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('今日队列', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  queue.isEmpty
                      ? '今天没有要背的词，休息一下'
                      : '到期复习 $dueCount 个 · 新词 $newCount 个',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: queue.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ReviewSessionPage(queue: queue),
                            ),
                          ),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始背词'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ 词库

class _WordbooksTab extends ConsumerWidget {
  const _WordbooksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wordbooks =
        ref.watch(wordbooksProvider).dataOrNull ?? const <Wordbook>[];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '词库',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () => openWordImport(context),
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('导入'),
              ),
              TextButton.icon(
                onPressed: () => _createWordbook(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建'),
              ),
            ],
          ),
        ),
        Expanded(
          child: wordbooks.isEmpty
              ? const Center(child: Text('还没有词库'))
              : ListView.separated(
                  itemCount: wordbooks.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final book = wordbooks[index];
                    return ListTile(
                      title: Text(book.name),
                      subtitle: Text(
                        '${book.wordCount} 词 · '
                        '${book.source == 'builtin' ? '内置' : '自建'}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '删除词库',
                        onPressed: () => _deleteWordbook(context, ref, book),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => WordListPage(wordbook: book),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _deleteWordbook(
    BuildContext context,
    WidgetRef ref,
    Wordbook book,
  ) async {
    // 删除后列表项会被移除，提前取好 Messenger 以显示提示。
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除词库？'),
        content: Text(
          '「${book.name}」及其 ${book.wordCount} 个单词将移入回收站，可在回收站恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(studyRepositoryProvider).deleteWordbook(book.id);
    messenger.showSnackBar(
      SnackBar(content: Text('已移入回收站：${book.name}')),
    );
  }

  Future<void> _createWordbook(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _WordbookNameDialog(
        onCreate: (name) =>
            ref.read(studyRepositoryProvider).createWordbook(name: name),
      ),
    );
  }
}

/// 新建词库对话框。
///
/// 控制器由对话框自己持有：若在 `showDialog` 返回后立刻 dispose，
/// 退场动画期间 TextField 仍会重建，触发「used after being disposed」。
class _WordbookNameDialog extends StatefulWidget {
  const _WordbookNameDialog({required this.onCreate});

  final Future<void> Function(String name) onCreate;

  @override
  State<_WordbookNameDialog> createState() => _WordbookNameDialogState();
}

class _WordbookNameDialogState extends State<_WordbookNameDialog> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    await widget.onCreate(name);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建词库'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '词库名称'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: const Text('创建'),
        ),
      ],
    );
  }
}

/// 某个词库下的单词列表（可增删）。
class WordListPage extends ConsumerWidget {
  const WordListPage({super.key, required this.wordbook});

  final Wordbook wordbook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words =
        ref.watch(wordsProvider(wordbook.id)).dataOrNull ?? const <WordEntry>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(wordbook.name),
        actions: [
          IconButton(
            tooltip: '批量导入',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: () => openWordImport(context),
          ),
          IconButton(
            tooltip: '添加单词',
            icon: const Icon(Icons.add),
            onPressed: () => _addWord(context, ref),
          ),
        ],
      ),
      body: words.isEmpty
          ? const Center(child: Text('这个词库还没有单词'))
          : ListView.separated(
              itemCount: words.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final word = words[index];
                return ListTile(
                  title: Text(word.spelling),
                  subtitle: Text(
                    word.meanings.isEmpty
                        ? '（无释义）'
                        : word.meanings.join('；'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PronounceButton(text: word.spelling),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => ref
                            .read(studyRepositoryProvider)
                            .deleteWord(word.id),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _addWord(BuildContext context, WidgetRef ref) async {
    final spelling = TextEditingController();
    final meanings = TextEditingController();
    final phonetic = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加单词'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: spelling,
                autofocus: true,
                decoration: const InputDecoration(labelText: '拼写'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: meanings,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '释义',
                  hintText: '多个释义用换行分隔',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phonetic,
                decoration: const InputDecoration(labelText: '音标（可选）'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final value = spelling.text.trim();
              if (value.isEmpty) return;
              final repository = ref.read(studyRepositoryProvider);
              if (await repository.hasWord(wordbook.id, value)) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('该词已存在')),
                  );
                }
                return;
              }
              await repository.addWord(
                wordbookId: wordbook.id,
                spelling: value,
                meanings: meanings.text
                    .split('\n')
                    .map((line) => line.trim())
                    .where((line) => line.isNotEmpty)
                    .toList(),
                phoneticUk:
                    phonetic.text.trim().isEmpty ? null : phonetic.text.trim(),
              );
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );

    spelling.dispose();
    meanings.dispose();
    phonetic.dispose();
  }
}

// ------------------------------------------------------------ 统计

class _StatsTab extends ConsumerStatefulWidget {
  const _StatsTab();

  @override
  ConsumerState<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends ConsumerState<_StatsTab> {
  StatsPeriod _period = StatsPeriod.month;
  DateTime _anchor = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final (start, end) = _period.rangeOf(_anchor);
    final stats = ref
            .watch(studyStatsProvider((start: start, end: end)))
            .dataOrNull ??
        const <StudyStatEntry>[];
    final summary = summarizeStudy(stats);
    final points = studyTrend(stats, _period, _anchor);
    final quiz = ref
            .watch(quizSessionsProvider((start: start, end: end)))
            .dataOrNull ??
        const <QuizSessionEntry>[];
    final quizSummary = summarizeQuizSessions(quiz);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        SegmentedButton<StatsPeriod>(
          segments: [
            for (final period in StatsPeriod.values)
              ButtonSegment(value: period, label: Text(period.label)),
          ],
          selected: {_period},
          showSelectedIcon: false,
          onSelectionChanged: (values) =>
              setState(() => _period = values.first),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(
                _period == StatsPeriod.year
                    ? '${_anchor.year} 年'
                    : '${_anchor.year} 年 ${_anchor.month} 月',
              ),
              onPressed: _pickDate,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: StatCard(label: '新词', value: '${summary.newCount} 个'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(label: '复习', value: '${summary.reviewCount} 次'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: '正确率',
                value: summary.total == 0
                    ? '—'
                    : '${(summary.correctRate * 100).toStringAsFixed(0)}%',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: '总用时',
                value: summary.durationSec == 0
                    ? '—'
                    : formatStudyDuration(summary.durationSec),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('学习量趋势', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                LineTrendChart(
                  points: points,
                  decimals: 0,
                  tooltipValueFormatter: (value) =>
                      '${value.toStringAsFixed(0)} 个词',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('测验战绩', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: '测验次数',
                        value: '${quizSummary.sessions} 次',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        label: '答题量',
                        value: '${quizSummary.questions} 题',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: '测验正确率',
                        value: quizSummary.questions == 0
                            ? '—'
                            : '${(quizSummary.accuracy * 100).toStringAsFixed(0)}%',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        label: '测验用时',
                        value: quizSummary.durationSec == 0
                            ? '—'
                            : formatStudyDuration(quizSummary.durationSec),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _anchor = picked);
  }
}
