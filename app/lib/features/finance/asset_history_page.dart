/// 资产历史统计页：按周 / 月 / 年查看净资产变动。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_x.dart';
import '../../core/period.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/finance_assets.dart';
import '../../data/finance_history.dart';
import '../../shared/line_trend_chart.dart';
import '../../shared/period_strip.dart';
import 'finance_providers.dart';

class AssetHistoryPage extends ConsumerStatefulWidget {
  const AssetHistoryPage({super.key});

  @override
  ConsumerState<AssetHistoryPage> createState() => _AssetHistoryPageState();
}

class _AssetHistoryPageState extends ConsumerState<AssetHistoryPage> {
  ViewPeriod _period = ViewPeriod.month;
  late final DateTime _now;
  late DateTime _anchor;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _anchor = _now;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts =
        ref.watch(accountsProvider).dataOrNull ?? const <Account>[];
    final flows =
        ref.watch(assetFlowsProvider).dataOrNull ?? const <AssetFlow>[];
    final summary = summarizeAssets(
      [
        for (final account in accounts)
          AssetAccount(
            id: account.id,
            type: account.type,
            balanceInit: account.balanceInit,
            marketAdjustment: account.marketAdjustment,
          ),
      ],
      flows,
    );
    final points = buildAssetHistory(
      period: _period,
      now: _now,
      currentNetWorth: summary.netWorth,
      flows: flows,
    );
    final options = periodOptions(_period, _now);
    final selected = _selectedPoint(points, options);
    final chartPoints = [
      for (final point in points)
        MetricPoint(
          bucket: _bucketLabel(point.option.anchor),
          value: point.change / 100,
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('资产历史统计')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SegmentedButton<ViewPeriod>(
            segments: [
              for (final period in ViewPeriod.values)
                ButtonSegment(value: period, label: Text(period.label)),
            ],
            selected: {_period},
            showSelectedIcon: false,
            onSelectionChanged: (values) => setState(() {
              _period = values.first;
              _anchor = _now;
            }),
          ),
          const SizedBox(height: 4),
          PeriodStrip(
            options: options,
            selectedKey: selected.option.key,
            onSelected: (option) => setState(() => _anchor = option.anchor),
          ),
          const SizedBox(height: 16),
          if (accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text('还没有账户，先去资产管家添加')),
            )
          else ...[
            _ChangeCard(point: selected, period: _period),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('变动趋势', style: theme.textTheme.titleMedium),
                        const Spacer(),
                        Text(
                          '单位：元',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '当前周期为正、历史周期为负时，折线跨越 0 轴',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 8),
                    LineTrendChart(points: chartPoints, decimals: 0),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final point in points.reversed)
                    _HistoryTile(
                      point: point,
                      selected: point.option.key == selected.option.key,
                      onTap: () =>
                          setState(() => _anchor = point.option.anchor),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '按已有收支流水回溯计算；转账不改变净资产，手动调整投资市值不计入历史变动。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ],
      ),
    );
  }

  AssetPeriodPoint _selectedPoint(
    List<AssetPeriodPoint> points,
    List<PeriodOption> options,
  ) {
    for (final option in options.reversed) {
      final (start, end) = _period.rangeOf(option.anchor);
      if (!_anchor.isBefore(start) && !_anchor.isAfter(end)) {
        for (final point in points) {
          if (point.option.key == option.key) return point;
        }
      }
    }
    return points.last;
  }

  String _bucketLabel(DateTime anchor) => _period == ViewPeriod.year
      ? '${anchor.year}-${anchor.month.toString().padLeft(2, '0')}'
      : formatDate(anchor);
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.point, required this.period});

  final AssetPeriodPoint point;
  final ViewPeriod period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = point.change;
    final color = change == 0
        ? theme.colorScheme.onSurface
        : (change > 0 ? const Color(0xFF2E9E62) : theme.colorScheme.error);
    final previousLabel = switch (period) {
      ViewPeriod.week => '较上周',
      ViewPeriod.month => '较上月',
      ViewPeriod.year => '较去年',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${point.option.label} · $previousLabel',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const Spacer(),
                Text(
                  '${point.changeCount} 笔收支',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _signedMoney(change),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: '本期期末净资产',
                    value: formatCents(point.endNetWorth),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: '上期期末净资产',
                    value: formatCents(point.previousNetWorth),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '¥$value',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.point,
    required this.selected,
    required this.onTap,
  });

  final AssetPeriodPoint point;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = point.change;
    final color = change == 0
        ? theme.colorScheme.outline
        : (change > 0 ? const Color(0xFF2E9E62) : theme.colorScheme.error);

    return ListTile(
      selected: selected,
      selectedTileColor:
          theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
      title: Text(point.option.label),
      subtitle: Text(
        '期末 ¥${formatCents(point.endNetWorth)} · ${point.changeCount} 笔收支',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
      ),
      trailing: Text(
        _signedMoney(change),
        style: theme.textTheme.titleSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
    );
  }
}

String _signedMoney(int cents) {
  final sign = cents > 0 ? '+' : (cents < 0 ? '-' : '');
  return '$sign¥${formatCents(cents.abs())}';
}
