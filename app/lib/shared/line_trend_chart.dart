/// 折线趋势图（体重 / 围度等单值指标），支持空档断线。
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/utils.dart';

class LineTrendChart extends StatefulWidget {
  const LineTrendChart({
    super.key,
    required this.points,
    this.decimals = 1,
    this.labelDivisor = 1,
    this.yLabelFormatter,
    this.tooltipValueFormatter,
  });

  final List<MetricPoint> points;

  /// Y 轴数值保留的小数位。
  final int decimals;

  /// Y 轴刻度换算除数：体重用 1000（克→千克）、围度用 10（毫米→厘米）。
  final double labelDivisor;

  /// 自定义 Y 轴刻度文案（如金额用「万」缩写）；为空时按 [decimals] 格式。
  final String Function(double value)? yLabelFormatter;

  /// 点选数据点后显示的数值文案；为空时使用 Y 轴刻度格式。
  final String Function(double value)? tooltipValueFormatter;

  @override
  State<LineTrendChart> createState() => _LineTrendChartState();
}

class _LineTrendChartState extends State<LineTrendChart> {
  /// 点选后保持选中的桶下标，点一下图表即可在图下看到具体数值。
  int? _selected;

  int? get _active {
    final index = _selected;
    if (index == null || index < 0 || index >= widget.points.length) {
      return null;
    }
    return index;
  }

  String _labelFor(double value) =>
      widget.yLabelFormatter?.call(value) ??
      (value / widget.labelDivisor).toStringAsFixed(widget.decimals);

  String _valueText(double value) =>
      widget.tooltipValueFormatter?.call(value) ?? _labelFor(value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = widget.points;
    final values = [
      for (final point in points)
        if (point.value != null) point.value!,
    ];

    if (values.isEmpty) {
      return SizedBox(
        height: 200,
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

    var minValue = values.reduce((a, b) => a < b ? a : b);
    var maxValue = values.reduce((a, b) => a > b ? a : b);
    if (minValue == maxValue) {
      // 单点数据：按量级留出 2% 的上下留白，避免刻度全挤成同一个值
      final span = maxValue.abs() < 1 ? 1.0 : maxValue.abs() * 0.02;
      minValue -= span;
      maxValue += span;
    }
    final padding = (maxValue - minValue) * 0.2;
    minValue -= padding;
    maxValue += padding;

    final spots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      final value = points[i].value;
      if (value != null) spots.add(FlSpot(i.toDouble(), value));
    }

    // 手机宽度有限，最多显示 6 个 X 轴标签；只在有数据的点上取，避免空白日期占位。
    final filledIndexes = [
      for (var i = 0; i < points.length; i++)
        if (points[i].value != null) i,
    ];
    final step = (filledIndexes.length / 6).ceil();
    final labelIndexes = <int>{
      for (var i = 0; i < filledIndexes.length; i += step) filledIndexes[i],
    };
    final brand = theme.colorScheme.primary;
    final interval = (maxValue - minValue) / 4;
    // 按当前字体倍率实际测量刻度宽度，避免大字体或大数值下被裁掉。
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
    for (final sample in [
      minValue,
      maxValue,
      0.0,
      minValue + interval,
      maxValue - interval,
    ]) {
      final width = measureWidth(_labelFor(sample));
      if (width > leftReserved) leftReserved = width;
    }
    leftReserved += 16;
    final bottomPainter = TextPainter(
      text: TextSpan(text: '10-01', style: labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    final bottomReserved = bottomPainter.height + 8;

    final bar = LineChartBarData(
      spots: spots,
      isCurved: false,
      color: brand,
      barWidth: 2,
      dotData: FlDotData(show: spots.length <= 40),
      belowBarData: BarAreaData(
        show: true,
        color: brand.withValues(alpha: 0.12),
      ),
    );
    // 只在该桶有数据时显示浮层；空白桶不显示。
    final active = _active;
    final activeSpot = active == null
        ? null
        : spots.where((spot) => spot.x == active.toDouble()).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 220,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LineChart(
              LineChartData(
                minY: minValue,
                maxY: maxValue,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                // 由外部维护浮层：松开手指后仍保留，直到切换页面或周期。
                showingTooltipIndicators: activeSpot == null
                    ? const []
                    : [
                        ShowingTooltipIndicators([
                          LineBarSpot(bar, 0, activeSpot),
                        ]),
                      ],
                lineTouchData: LineTouchData(
                  enabled: true,
                  // 关闭内置触摸浮层，否则抬手时会被清空。
                  handleBuiltInTouches: false,
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
                          '${_valueText(spot.y)}',
                          TextStyle(
                            color: theme.colorScheme.onInverseSurface,
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
                      interval: interval,
                      // 不额外补 min / max 标签，避免与按 interval 生成的刻度
                      // 挤在一起，出现 19、-34、-67 这类不均匀且重叠的文案。
                      minIncluded: false,
                      maxIncluded: false,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        space: 6,
                        child: Text(
                          _labelFor(value),
                          maxLines: 1,
                          softWrap: false,
                          textAlign: TextAlign.right,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: bottomReserved,
                      // 固定按 1 调用，由 labelIndexes 决定哪些点显示，避免与
                      // fl_chart 自身的刻度间隔叠加后标签缺失。
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= points.length) {
                          return const SizedBox.shrink();
                        }
                        if (!labelIndexes.contains(index)) {
                          return const SizedBox.shrink();
                        }
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
                lineBarsData: [bar],
              ),
            ),
          ),
        ),
        _SelectionReadout(
          text: _readoutText(),
        ),
      ],
    );
  }

  String _readoutText() {
    final index = _active;
    if (index == null) return '点击图表可查看具体数值';
    final value = widget.points[index].value;
    if (value == null) return '点击图表可查看具体数值';
    return '${formatBucketTitle(widget.points[index].bucket)} · ${_valueText(value)}';
  }
}

/// 图表下方的点选结果：始终占一行，避免选中后布局跳动。
class _SelectionReadout extends StatelessWidget {
  const _SelectionReadout({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
