/// 图表组件：分类占比饼图与收支趋势折线图（基于 fl_chart）。
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../data/finance_stats.dart';

class PieSlice {
  const PieSlice({required this.label, required this.amount});

  final String label;
  final int amount;
}

const _palette = <Color>[
  Color(0xFF02743B),
  Color(0xFF0FDC78),
  Color(0xFF85FABF),
  Color(0xFF80C1FF),
  Color(0xFF27D2BF),
  Color(0xFFF87454),
  Color(0xFFD3D4DA),
];

class CategoryPieChart extends StatelessWidget {
  const CategoryPieChart({super.key, required this.slices});

  final List<PieSlice> slices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (slices.isEmpty) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Text(
            '该区间还没有数据',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      );
    }

    final total = slices.fold<int>(0, (sum, slice) => sum + slice.amount);
    // 只有一个分类时扇区占满整圆，fl_chart 不会在扇区内绘制标题，
    // 改为在圆环中心显示分类名与 100%，避免「看不到占比」。
    final single = slices.length == 1 ? slices.single : null;

    return SizedBox(
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 52,
              startDegreeOffset: -90,
              sections: [
                for (var i = 0; i < slices.length; i++)
                  PieChartSectionData(
                    value: slices[i].amount.toDouble(),
                    color: _palette[i % _palette.length],
                    radius: 52,
                    title: total == 0 || single != null
                        ? ''
                        : formatRatio(slices[i].amount / total),
                    titleStyle: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (single != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  single.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                Text(
                  formatRatio(1),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class TrendLineChart extends StatefulWidget {
  const TrendLineChart({super.key, required this.points});

  final List<TrendPoint> points;

  static const incomeColor = Color(0xFF0FDC78);
  static const expenseColor = Color(0xFF80C1FF);

  @override
  State<TrendLineChart> createState() => _TrendLineChartState();
}

class _TrendLineChartState extends State<TrendLineChart> {
  /// 点选后保持选中的桶下标。
  int? _selected;

  int? get _active {
    final index = _selected;
    if (index == null || index < 0 || index >= widget.points.length) {
      return null;
    }
    return index;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = widget.points;
    final hasData =
        points.isNotEmpty && points.any((p) => p.income > 0 || p.expense > 0);

    if (!hasData) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Text(
            '该区间还没有数据',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      );
    }

    var maxValue = 0;
    for (final point in points) {
      if (point.income > maxValue) maxValue = point.income;
      if (point.expense > maxValue) maxValue = point.expense;
    }
    final maxY = maxValue == 0 ? 100.0 : maxValue * 1.2;

    // 一周只有 7 个点，直接显示日号；更长的周期最多 6 个日期标签，
    // 避免小屏或大字体下互相重叠。
    final compact = points.length <= 7;
    final step = compact ? 1 : (points.length / 6).ceil();

    // 按当前字体倍率测量轴标签，取所有刻度里最宽的一条，避免大金额被裁掉。
    final labelStyle = theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11);
    final textScaler = MediaQuery.textScalerOf(context);
    double measureWidth(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      return painter.width;
    }

    var leftReserved = 0.0;
    for (var index = 0; index <= 4; index++) {
      final width = measureWidth(
        _formatAxisAmount((maxY * index / 4).round()),
      );
      if (width > leftReserved) leftReserved = width;
    }
    leftReserved += 16;
    final bottomPainter = TextPainter(
      text: TextSpan(text: '10-01', style: labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    final bottomReserved = bottomPainter.height + 8;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 240,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.4),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchCallback: (event, response) {
                    final spot = response?.lineBarSpots?.firstOrNull;
                    if (spot == null) return;
                    final index = spot.x.round();
                    if (index < 0 || index >= points.length) return;
                    if (index != _selected) {
                      setState(() => _selected = index);
                    }
                  },
                  touchTooltipData: LineTouchTooltipData(
                    maxContentWidth: 220,
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    tooltipBorderRadius: BorderRadius.circular(10),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                    getTooltipItems: (touchedSpots) => [
                      for (final spot in touchedSpots)
                        LineTooltipItem(
                          '${formatBucketTitle(points[spot.x.toInt()].bucket)}\n'
                          '${spot.barIndex == 0 ? '收入' : '支出'} '
                          '¥${formatCents(spot.y.round())}',
                          TextStyle(
                            color: spot.barIndex == 0
                                ? TrendLineChart.incomeColor
                                : const Color(0xFFBBD9FF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: leftReserved,
                      interval: maxY / 4,
                      getTitlesWidget: (value, meta) => Text(
                        value <= 0 ? '' : _formatAxisAmount(value.round()),
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.right,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: bottomReserved,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= points.length) {
                          return const SizedBox.shrink();
                        }
                        if (index % step != 0) return const SizedBox.shrink();
                        final bucket = points[index].bucket;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            formatAxisBucketLabel(bucket, points.length),
                            maxLines: 1,
                            softWrap: false,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  _line(
                    points,
                    TrendLineChart.incomeColor,
                    (point) => point.income,
                  ),
                  _line(
                    points,
                    TrendLineChart.expenseColor,
                    (point) => point.expense,
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 2),
          child: Text(
            _readoutText(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _readoutText() {
    final index = _active;
    if (index == null) return '点击图表可查看当天数值';
    final point = widget.points[index];
    return '${formatBucketTitle(point.bucket)} · '
        '收入 ¥${formatCents(point.income)}'
        ' · 支出 ¥${formatCents(point.expense)}';
  }

  LineChartBarData _line(
    List<TrendPoint> points,
    Color color,
    int Function(TrendPoint) valueOf,
  ) {
    return LineChartBarData(
      spots: [
        for (var i = 0; i < points.length; i++)
          FlSpot(i.toDouble(), valueOf(points[i]).toDouble()),
      ],
      isCurved: false,
      color: color,
      barWidth: 2,
      dotData: FlDotData(show: points.length <= 12),
    );
  }

  /// Y 轴金额：万元以上用「万」、亿元以上用「亿」，避免大字体下刻度换行。
  String _formatAxisAmount(int cents) {
    final yuan = cents / 100;
    if (yuan >= 100000000) {
      return '¥${(yuan / 100000000).toStringAsFixed(1)}亿';
    }
    if (yuan >= 10000) return '¥${(yuan / 10000).toStringAsFixed(1)}万';
    return '¥${formatCents(cents)}';
  }
}
