/// 围度图表：六条折线（选中高亮）与综合雷达图。
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../data/health_stats.dart';

/// 一个部位的折线序列。
class MeasureSeries {
  const MeasureSeries({required this.part, required this.points});

  final String part;
  final List<MetricPoint> points;
}

/// 每个部位的固定配色，保证六条线可区分。
const measurePartColors = <String, Color>{
  '胸围': Color(0xFF4E79F5),
  '腰围': Color(0xFFF2994A),
  '臀围': Color(0xFF27AE60),
  '臂围': Color(0xFF9B51E0),
  '大腿围': Color(0xFFEB5757),
  '小腿围': Color(0xFF2D9CDB),
  '颈围': Color(0xFF8D6E63),
};

Color measurePartColor(String part) =>
    measurePartColors[part] ?? const Color(0xFF4E79F5);

/// 多条围度折线：选中的部位高亮，其余半透明。
class MeasureTrendChart extends StatelessWidget {
  const MeasureTrendChart({
    super.key,
    required this.series,
    required this.selectedPart,
  });

  final List<MeasureSeries> series;
  final String selectedPart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = [
      for (final item in series)
        for (final point in item.points)
          if (point.value != null) point.value!,
    ];

    if (values.isEmpty) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Text(
            '该区间还没有围度数据',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      );
    }

    var minValue = values.reduce((a, b) => a < b ? a : b);
    var maxValue = values.reduce((a, b) => a > b ? a : b);
    if (maxValue - minValue < 1) {
      minValue -= 10;
      maxValue += 10;
    }
    final padding = (maxValue - minValue) * 0.15;
    minValue -= padding;
    maxValue += padding;

    final buckets = series.isEmpty
        ? const <MetricPoint>[]
        : series.first.points;

    final filledIndexes = [
      for (var i = 0; i < buckets.length; i++)
        if (buckets[i].value != null ||
            series.any((item) => item.points[i].value != null))
          i,
    ];
    final step = filledIndexes.isEmpty ? 1 : (filledIndexes.length / 6).ceil();
    final labelIndexes = <int>{
      for (var i = 0; i < filledIndexes.length; i += step) filledIndexes[i],
    };

    final labelStyle =
        theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11);
    final textScaler = MediaQuery.textScalerOf(context);
    double measureWidth(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      return painter.width;
    }

    final topLabel = (maxValue / 10).toStringAsFixed(1);
    final bottomLabel = (minValue / 10).toStringAsFixed(1);
    final leftReserved = measureWidth(
          topLabel.length >= bottomLabel.length ? topLabel : bottomLabel,
        ) +
        12;

    return SizedBox(
      height: 230,
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
                    (value / 10).toStringAsFixed(1),
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
                  reservedSize: 28,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= buckets.length) {
                      return const SizedBox.shrink();
                    }
                    if (!labelIndexes.contains(index)) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        formatBucketLabel(buckets[index].bucket),
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
              for (final item in series)
                _lineFor(item, item.part == selectedPart),
            ],
          ),
        ),
      ),
    );
  }

  LineChartBarData _lineFor(MeasureSeries item, bool highlighted) {
    final color = measurePartColor(item.part);
    final spots = <FlSpot>[];
    for (var i = 0; i < item.points.length; i++) {
      final value = item.points[i].value;
      if (value != null) spots.add(FlSpot(i.toDouble(), value));
    }
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: color.withValues(alpha: highlighted ? 1 : 0.22),
      barWidth: highlighted ? 2.6 : 1.2,
      dotData: FlDotData(show: highlighted && spots.length <= 40),
      belowBarData: BarAreaData(
        show: highlighted,
        color: color.withValues(alpha: 0.1),
      ),
    );
  }
}

/// 综合雷达图：六个核心围度的最新值。
class MeasureRadarChart extends StatelessWidget {
  const MeasureRadarChart({
    super.key,
    required this.latest,
  });

  /// 部位 -> 毫米。
  final Map<String, int> latest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final present = [
      for (final part in coreMeasureParts) ?latest[part],
    ];

    if (present.isEmpty) {
      return SizedBox(
        height: 240,
        child: Center(
          child: Text(
            '至少记录一个部位后生成综合雷达图',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      );
    }

    final minValue = present.reduce((a, b) => a < b ? a : b) / 10;
    final fallback = minValue;
    final entries = [
      for (final part in coreMeasureParts)
        RadarEntry(value: (latest[part] ?? (fallback * 10).round()) / 10),
    ];

    final primary = theme.colorScheme.primary;
    return SizedBox(
      height: 260,
      child: RadarChart(
        RadarChartData(
          dataSets: [
            RadarDataSet(
              dataEntries: entries,
              fillColor: primary.withValues(alpha: 0.18),
              borderColor: primary,
              borderWidth: 2,
              entryRadius: 2.5,
            ),
          ],
          radarBackgroundColor: primary.withValues(alpha: 0.04),
          radarBorderData: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 1,
          ),
          gridBorderData: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
          tickBorderData: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 1,
          ),
          tickCount: 3,
          // 雷达图刻度按「相对最小值」绘制，数字会与真实厘米值不符；
          // 具体数值由上方 2×3 卡片展示，这里隐藏刻度文字。
          ticksTextStyle: const TextStyle(fontSize: 9, color: Colors.transparent),
          titleTextStyle: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          titlePositionPercentageOffset: 0.16,
          getTitle: (index, angle) {
            if (index < 0 || index >= coreMeasureParts.length) {
              return const RadarChartTitle(text: '');
            }
            return RadarChartTitle(
              text: coreMeasureParts[index],
              angle: angle,
            );
          },
          isMinValueAtCenter: true,
          radarTouchData: RadarTouchData(enabled: false),
        ),
      ),
    );
  }
}
