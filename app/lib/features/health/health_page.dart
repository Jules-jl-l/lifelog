/// 健康模块：体重 / 围度 / 运动的记录与周、月、年对比。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_x.dart';
import '../../core/period.dart';
import '../../core/utils.dart';
import '../../data/health_stats.dart';
import '../../data/providers.dart';
import '../../data/settings_repository.dart';
import '../../shared/line_trend_chart.dart';
import '../../shared/period_strip.dart';
import '../../shared/stat_card.dart';
import 'health_providers.dart';
import 'record_editors.dart';

class HealthPage extends ConsumerStatefulWidget {
  const HealthPage({super.key});

  @override
  ConsumerState<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends ConsumerState<HealthPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  ViewPeriod _period = ViewPeriod.month;
  late final DateTime _now;
  late DateTime _anchor;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _anchor = _now;
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  HealthRangeKey get _range {
    final (start, end) = _period.rangeOf(_anchor);
    return (start: start, end: end);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final range = _range;
    final options = periodOptions(_period, _now);
    final selectedKey = _selectedPeriodKey(options);
    final measureEntries =
        ref.watch(measureEntriesProvider(range)).dataOrNull ??
            const <MeasureEntry>[];
    final knownParts = measureParts(measureEntries);

    return Scaffold(
      appBar: AppBar(
        title: const Text('健康'),
        actions: [
          IconButton(
            tooltip: '设置身高（用于 BMI）',
            icon: const Icon(Icons.straighten),
            onPressed: () => _editHeight(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditorFor(_tabs.index, knownParts),
        icon: const Icon(Icons.add),
        label: Text(const ['记体重', '记围度', '记运动'][_tabs.index]),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<ViewPeriod>(
              segments: [
                for (final period in ViewPeriod.values)
                  ButtonSegment(value: period, label: Text(period.label)),
              ],
              selected: {_period},
              showSelectedIcon: false,
              onSelectionChanged: (values) =>
                  setState(() => _period = values.first),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: PeriodStrip(
              options: options,
              selectedKey: selectedKey,
              onSelected: (option) => setState(() => _anchor = option.anchor),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    periodRangeHint(_period, range.start, range.end),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            labelColor: theme.colorScheme.primary,
            tabs: const [Tab(text: '体重'), Tab(text: '围度'), Tab(text: '运动')],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                WeightTab(range: range, period: _period, anchor: _anchor),
                MeasureTab(range: range, period: _period, anchor: _anchor),
                WorkoutTab(range: range),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _selectedPeriodKey(List<PeriodOption> options) {
    for (final option in options.reversed) {
      final (start, end) = _period.rangeOf(option.anchor);
      if (!_anchor.isBefore(start) && !_anchor.isAfter(end)) {
        return option.key;
      }
    }
    return options.last.key;
  }

  void _openEditorFor(int index, List<String> knownParts) {
    switch (index) {
      case 0:
        openWeightEditor(context);
      case 1:
        openMeasureEditor(context, knownParts: knownParts);
      default:
        openWorkoutEditor(context);
    }
  }

  Future<void> _editHeight(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(
      text: ref.read(heightCmProvider).dataOrNull?.toString() ?? '',
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('身高'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '身高（cm）',
            hintText: '用于计算 BMI',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final value = int.tryParse(controller.text.trim());
              final repository = ref.read(settingsRepositoryProvider);
              if (value == null || value <= 0) {
                await repository.remove(SettingKeys.heightCm);
              } else {
                await repository.set(SettingKeys.heightCm, '$value');
              }
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ 体重

class WeightTab extends ConsumerWidget {
  const WeightTab({
    super.key,
    required this.range,
    required this.period,
    required this.anchor,
  });

  final HealthRangeKey range;
  final ViewPeriod period;
  final DateTime anchor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entries = ref.watch(weightEntriesProvider(range)).dataOrNull ??
        const <WeightEntry>[];
    final latest = ref.watch(latestWeightProvider).dataOrNull;
    final height = ref.watch(heightCmProvider).dataOrNull;

    final summary = summarizeWeight(entries);
    final points = weightTrend(entries, period, anchor);
    final bmi = bmiOf(latest?.grams, height);
    final delta = summary.deltaGrams;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: '当前体重',
                value: latest == null ? '—' : '${formatKg(latest.grams)} kg',
                hint: latest == null ? '还没有记录' : formatDate(latest.at),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: '区间变化',
                value: delta == null
                    ? '—'
                    : '${delta > 0 ? '+' : ''}${formatKg(delta)} kg',
                hint: '共 ${summary.count} 次',
                color: delta == null
                    ? null
                    : (delta > 0
                        ? const Color(0xFFE8463A)
                        : const Color(0xFF05994F)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: '区间最低',
                value: summary.minGrams == null
                    ? '—'
                    : '${formatKg(summary.minGrams!)} kg',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: '区间最高',
                value: summary.maxGrams == null
                    ? '—'
                    : '${formatKg(summary.maxGrams!)} kg',
              ),
            ),
          ],
        ),
        if (bmi != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.speed),
              title: Text('BMI ${bmi.toStringAsFixed(1)}'),
              subtitle: Text('${bmiLabel(bmi)} · 身高 $height cm'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('体重趋势', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    Text(
                      period == ViewPeriod.year ? '按月' : '按天',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LineTrendChart(points: points, labelDivisor: 1000),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              for (final entry in entries.reversed)
                ListTile(
                  title: Text('${formatKg(entry.grams)} kg'),
                  subtitle: Text(formatDateTime(entry.at)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openWeightEditor(context, existing: entry),
                ),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('该区间还没有体重记录'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ 围度

class MeasureTab extends ConsumerStatefulWidget {
  const MeasureTab({
    super.key,
    required this.range,
    required this.period,
    required this.anchor,
  });

  final HealthRangeKey range;
  final ViewPeriod period;
  final DateTime anchor;

  @override
  ConsumerState<MeasureTab> createState() => _MeasureTabState();
}

class _MeasureTabState extends ConsumerState<MeasureTab> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = ref.watch(measureEntriesProvider(widget.range)).dataOrNull ??
        const <MeasureEntry>[];
    final parts = measureParts(entries);
    final selected = _selected ?? (parts.isEmpty ? null : parts.first);

    final latest = <String, MeasureEntry>{
      for (final entry in entries) entry.part: entry,
    };
    final points = selected == null
        ? const <MetricPoint>[]
        : measureTrend(entries, selected, widget.period, widget.anchor);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        if (parts.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final part in parts)
                ChoiceChip(
                  label: Text(part),
                  selected: selected == part,
                  onSelected: (_) => setState(() => _selected = part),
                ),
            ],
          ),
        if (selected != null) ...[
          const SizedBox(height: 12),
          StatCard(
            label: '$selected 最新',
            value: latest[selected] == null
                ? '—'
                : '${formatCm(latest[selected]!.mm)} cm',
            hint: latest[selected] == null
                ? null
                : formatDate(latest[selected]!.at),
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
                      Text('$selected 趋势', style: theme.textTheme.titleMedium),
                      const Spacer(),
                      Text(
                        widget.period == ViewPeriod.year ? '按月' : '按天',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LineTrendChart(
                    points: points,
                    decimals: 1,
                    labelDivisor: 10,
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              for (final entry in entries.reversed)
                ListTile(
                  title: Text('${entry.part} ${formatCm(entry.mm)} cm'),
                  subtitle: Text(formatDateTime(entry.at)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      openMeasureEditor(context, existing: entry),
                ),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('该区间还没有围度记录'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ 运动

class WorkoutTab extends ConsumerWidget {
  const WorkoutTab({super.key, required this.range});

  final HealthRangeKey range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entries = ref.watch(workoutEntriesProvider(range)).dataOrNull ??
        const <WorkoutEntry>[];
    final summary = summarizeWorkouts(entries);
    final byType = minutesByType(entries);
    final maxMinutes = byType.isEmpty ? 0 : byType.first.minutes;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(label: '运动次数', value: '${summary.count} 次'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: '总时长',
                value: formatDuration(summary.minutes),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: '总距离',
                value: summary.meters == 0
                    ? '—'
                    : '${formatKm(summary.meters)} km',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: '总消耗',
                value: summary.calories == 0
                    ? '—'
                    : '${summary.calories} kcal',
              ),
            ),
          ],
        ),
        if (byType.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('按类型时长', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  for (final item in byType) ...[
                    Row(
                      children: [
                        SizedBox(width: 48, child: Text(item.type)),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: maxMinutes == 0
                                  ? 0
                                  : item.minutes / maxMinutes,
                              minHeight: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatDuration(item.minutes),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              for (final entry in entries.reversed)
                ListTile(
                  title: Text(
                    '${entry.type} · ${formatDuration(entry.minutes)}',
                  ),
                  subtitle: Text(
                    '${formatDateTime(entry.at)}'
                    '${entry.meters == null ? '' : ' · ${formatKm(entry.meters!)} km'}'
                    '${entry.calories == null ? '' : ' · ${entry.calories} kcal'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openWorkoutEditor(context, existing: entry),
                ),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('该区间还没有运动记录'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
