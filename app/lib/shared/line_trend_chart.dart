/// 折线趋势图（体重 / 围度等单值指标），支持空档断线。
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/utils.dart';

class LineTrendChart extends StatelessWidget {
  const LineTrendChart({
    super.key,
    required this.points,
    this.decimals = 1,
    this.labelDivisor = 1,
  });

  final List<MetricPoint> points;

  /// Y 轴数值保留的小数位。
  final int decimals;

  /// Y 轴刻度换算除数：体重用 1000（克→千克）、围度用 10（毫米→厘米）。
  final double labelDivisor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
    // 按当前字体倍率实际测量刻度宽度，避免大字体下被裁掉。
    final labelStyle = theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11);
    final textScaler = MediaQuery.textScalerOf(context);
    final topLabel = (maxValue / labelDivisor).toStringAsFixed(decimals);
    final bottomLabel = (minValue / labelDivisor).toStringAsFixed(decimals);
    double measureWidth(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      return painter.width;
    }

    final leftReserved = measureWidth(
          topLabel.length >= bottomLabel.length ? topLabel : bottomLabel,
        ) +
        12;
    final bottomPainter = TextPainter(
      text: TextSpan(text: '10-01', style: labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    final bottomReserved = bottomPainter.height + 8;

    return SizedBox(
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
              horizontalInterval: (maxValue - minValue) / 4,
              getDrawingHorizontalLine: (_) => FlLine(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
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
                  interval: (maxValue - minValue) / 4,
                  getTitlesWidget: (value, meta) => Text(
                    (value / labelDivisor).toStringAsFixed(decimals),
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
                        formatBucketLabel(bucket),
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
              LineChartBarData(
                spots: spots,
                isCurved: false,
                color: brand,
                barWidth: 2,
                dotData: FlDotData(show: spots.length <= 40),
                belowBarData: BarAreaData(
                  show: true,
                  color: brand.withValues(alpha: 0.12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
