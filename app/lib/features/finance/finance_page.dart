/// 财务总览：周 / 月 / 年汇总、周期横滑选择、收支趋势、分类占比与排行。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_x.dart';
import '../../core/period.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/finance_stats.dart';
import '../../shared/charts.dart';
import '../../shared/period_strip.dart';
import 'asset_manager_page.dart';
import 'finance_providers.dart';
import 'manage_page.dart';
import 'transaction_editor.dart';
import 'transactions_page.dart';

class FinancePage extends ConsumerStatefulWidget {
  const FinancePage({super.key});

  @override
  ConsumerState<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends ConsumerState<FinancePage> {
  ViewPeriod _period = ViewPeriod.month;
  late final DateTime _now;
  late DateTime _anchor;
  TxnKind _kind = TxnKind.expense;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _anchor = _now;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (start, end) = _period.rangeOf(_anchor);
    final entriesAsync = ref.watch(entriesProvider((start: start, end: end)));
    final categoriesAsync = ref.watch(categoriesProvider);

    final categoryNames = <String, String>{
      for (final item in categoriesAsync.dataOrNull ?? const <Category>[])
        item.id: item.name,
    };

    final entries = entriesAsync.dataOrNull ?? const <TxnEntry>[];
    final summary = summarize(entries);
    final items = breakdownByCategory(entries, _kind);
    final slices = [
      for (final item in items)
        PieSlice(
          label: _categoryName(item.categoryId, categoryNames),
          amount: item.amount,
        ),
    ];
    final points = buildTrend(entries, _period, _anchor);
    final options = periodOptions(_period, _now);
    final selectedKey = _selectedPeriodKey(options);
    final kindCount = entries.where((entry) => entry.kind == _kind).length;
    final kindTotal = _kind == TxnKind.expense ? summary.expense : summary.income;
    final average = kindCount == 0 ? 0 : (kindTotal / kindCount).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text('财务'),
        actions: [
          IconButton(
            tooltip: '资产管家',
            icon: const Icon(Icons.savings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AssetManagerPage(),
              ),
            ),
          ),
          IconButton(
            tooltip: '流水明细',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TransactionsPage()),
            ),
          ),
          IconButton(
            tooltip: '账户与分类',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ManagePage()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openTransactionEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          SegmentedButton<ViewPeriod>(
            segments: [
              for (final period in ViewPeriod.values)
                ButtonSegment(value: period, label: Text(period.label)),
            ],
            selected: {_period},
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: '收入',
                  value: summary.income,
                  color: const Color(0xFF05994F),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: '支出',
                  value: summary.expense,
                  color: const Color(0xFFE8463A),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(label: '结余', value: summary.net),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '共 ${summary.count} 笔',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  periodRangeHint(_period, start, end),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              Text(
                '平均 ¥${formatCents(average)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
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
                  Row(
                    children: [
                      Text('收支趋势', style: theme.textTheme.titleMedium),
                      const Spacer(),
                      Text(
                        _period == ViewPeriod.year ? '按月' : '按天',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: const [
                      _LegendDot(
                        color: TrendLineChart.incomeColor,
                        label: '收入',
                      ),
                      SizedBox(width: 16),
                      _LegendDot(
                        color: TrendLineChart.expenseColor,
                        label: '支出',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TrendLineChart(points: points),
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
                  Row(
                    children: [
                      Text('分类占比', style: theme.textTheme.titleMedium),
                      const Spacer(),
                      SegmentedButton<TxnKind>(
                        segments: const [
                          ButtonSegment(
                            value: TxnKind.expense,
                            label: Text('支出'),
                          ),
                          ButtonSegment(
                            value: TxnKind.income,
                            label: Text('收入'),
                          ),
                        ],
                        selected: {_kind},
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                        onSelectionChanged: (values) =>
                            setState(() => _kind = values.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CategoryPieChart(slices: slices),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('收支排行', style: theme.textTheme.titleMedium),
                      const Spacer(),
                      Text(
                        '${_kind.label} · 共 ${items.length} 类',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          '该区间还没有${_kind.label}数据',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    )
                  else
                    for (final item in items)
                      _RankingTile(
                        name: _categoryName(item.categoryId, categoryNames),
                        amount: item.amount,
                        ratio: item.ratio,
                        kind: _kind,
                      ),
                ],
              ),
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

  String _categoryName(String? id, Map<String, String> names) =>
      id == null ? '未分类' : (names[id] ?? '已删除分类');
}

// ------------------------------------------------------------ 排行

class _RankingTile extends StatelessWidget {
  const _RankingTile({
    required this.name,
    required this.amount,
    required this.ratio,
    required this.kind,
  });

  final String name;
  final int amount;
  final double ratio;
  final TxnKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _iconFor(name, kind),
              size: 20,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      formatRatio(ratio),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0, 1),
                    minHeight: 6,
                    backgroundColor:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '¥${formatCents(amount)}',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String name, TxnKind kind) {
    if (kind == TxnKind.income) {
      if (name.contains('工资') ||
          name.contains('薪') ||
          name.contains('奖金')) {
        return Icons.payments_outlined;
      }
      if (name.contains('理财') ||
          name.contains('投资') ||
          name.contains('收益')) {
        return Icons.trending_up;
      }
      return Icons.attach_money;
    }
    if (name.contains('零食')) return Icons.icecream_outlined;
    if (name.contains('餐') || name.contains('食')) {
      return Icons.restaurant_outlined;
    }
    if (name.contains('购物')) return Icons.shopping_bag_outlined;
    if (name.contains('交通') ||
        name.contains('地铁') ||
        name.contains('公交')) {
      return Icons.directions_bus_filled_outlined;
    }
    if (name.contains('出行') || name.contains('旅行')) {
      return Icons.flight_takeoff;
    }
    if (name.contains('娱乐')) return Icons.sports_esports_outlined;
    if (name.contains('通讯')) return Icons.phone_iphone;
    if (name.contains('住房') || name.contains('房租')) {
      return Icons.home_outlined;
    }
    if (name.contains('医疗') || name.contains('药')) {
      return Icons.local_hospital_outlined;
    }
    if (name.contains('学习') || name.contains('书')) {
      return Icons.menu_book_outlined;
    }
    return Icons.category_outlined;
  }
}

// ------------------------------------------------------------ 通用卡片

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.color});

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '¥${formatCents(value)}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
