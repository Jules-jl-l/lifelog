/// 学习模块：背词 / 词库 / 统计。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_x.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import '../../data/study/quiz.dart';
import '../../data/study_stats.dart';
import '../../shared/line_trend_chart.dart';
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

class _StudyPageState extends ConsumerState<StudyPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void initState() {
    super.initState();
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
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('学习')),
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            labelColor: theme.colorScheme.primary,
            tabs: const [
              Tab(text: '背词'),
              Tab(text: '测验'),
              Tab(text: '词库'),
              Tab(text: '统计'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                _ReviewTab(),
                QuizTab(),
                _WordbooksTab(),
                _StatsTab(),
              ],
            ),
          ),
        ],
      ),
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
                LineTrendChart(points: points, decimals: 0),
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
