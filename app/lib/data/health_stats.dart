/// 健康模块的统计纯函数：不依赖数据库，便于单元测试。
///
/// 存储单位约定：体重用「克」、围度用「毫米」，避免浮点误差。
/// 周期（周 / 月 / 年）复用 `core/period.dart`，与财务模块保持一致。
library;

import '../core/period.dart';
import '../core/utils.dart' show MetricPoint;

/// 体重记录。
class WeightEntry {
  const WeightEntry({required this.id, required this.at, required this.grams});

  final String id;
  final DateTime at;

  /// 克
  final int grams;
}

/// 围度记录（长表：一行一个部位）。
class MeasureEntry {
  const MeasureEntry({
    required this.id,
    required this.at,
    required this.part,
    required this.mm,
  });

  final String id;
  final DateTime at;
  final String part;

  /// 毫米
  final int mm;
}

/// 运动记录。
class WorkoutEntry {
  const WorkoutEntry({
    required this.id,
    required this.at,
    required this.minutes,
    required this.type,
    this.meters,
    this.calories,
    this.avgHr,
  });

  final String id;
  final DateTime at;
  final int minutes;
  final String type;
  final int? meters;
  final int? calories;
  final int? avgHr;
}

/// 围度默认部位顺序（未收录的部位会被追加到末尾）。
const defaultMeasureParts = <String>['胸围', '腰围', '臀围', '臂围', '大腿', '小腿', '颈围'];

/// 运动类型候选。
const workoutTypes = <String>['跑步', '快走', '骑行', '游泳', '力量', '其他'];

List<MetricPoint> _trendByBucket<T>(
  Iterable<T> items,
  ViewPeriod period,
  DateTime anchor,
  double Function(T item) valueOf,
  DateTime Function(T item) timeOf,
) {
  final sums = <String, double>{};
  final counts = <String, int>{};

  for (final item in items) {
    final key = periodBucketKeyOf(timeOf(item), period);
    sums[key] = (sums[key] ?? 0) + valueOf(item);
    counts[key] = (counts[key] ?? 0) + 1;
  }

  return [
    for (final key in periodBucketKeys(period, anchor))
      MetricPoint(
        bucket: key,
        value: counts[key] == null ? null : sums[key]! / counts[key]!,
      ),
  ];
}

/// 体重趋势：同一桶内多次称重取平均。
List<MetricPoint> weightTrend(
  Iterable<WeightEntry> entries,
  ViewPeriod period,
  DateTime anchor,
) =>
    _trendByBucket(
      entries,
      period,
      anchor,
      (item) => item.grams.toDouble(),
      (item) => item.at,
    );

/// 围度趋势：只统计指定部位。
List<MetricPoint> measureTrend(
  Iterable<MeasureEntry> entries,
  String part,
  ViewPeriod period,
  DateTime anchor,
) =>
    _trendByBucket(
      entries.where((item) => item.part == part),
      period,
      anchor,
      (item) => item.mm.toDouble(),
      (item) => item.at,
    );

/// 体重概览：区间内首次 / 最近 / 最高 / 最低。
class WeightSummary {
  const WeightSummary({
    this.firstGrams,
    this.latestGrams,
    this.minGrams,
    this.maxGrams,
    this.count = 0,
  });

  final int? firstGrams;
  final int? latestGrams;
  final int? minGrams;
  final int? maxGrams;
  final int count;

  /// 区间内的净变化（最近 - 首次）。
  int? get deltaGrams => (latestGrams != null && firstGrams != null)
      ? latestGrams! - firstGrams!
      : null;
}

WeightSummary summarizeWeight(Iterable<WeightEntry> entries) {
  final sorted = entries.toList()..sort((a, b) => a.at.compareTo(b.at));
  if (sorted.isEmpty) return const WeightSummary();

  var min = sorted.first.grams;
  var max = sorted.first.grams;
  for (final entry in sorted) {
    if (entry.grams < min) min = entry.grams;
    if (entry.grams > max) max = entry.grams;
  }

  return WeightSummary(
    firstGrams: sorted.first.grams,
    latestGrams: sorted.last.grams,
    minGrams: min,
    maxGrams: max,
    count: sorted.length,
  );
}

/// BMI = 体重(kg) / 身高(m)²。
double? bmiOf(int? grams, int? heightCm) {
  if (grams == null || heightCm == null || heightCm <= 0) return null;
  final meters = heightCm / 100;
  return grams / 1000 / (meters * meters);
}

/// 中国成人 BMI 分类。
String bmiLabel(double bmi) {
  if (bmi < 18.5) return '偏瘦';
  if (bmi < 24) return '正常';
  if (bmi < 28) return '偏胖';
  return '肥胖';
}

/// 出现过的部位，按默认顺序排列，未收录的追加在后面。
List<String> measureParts(Iterable<MeasureEntry> entries) {
  final present = {for (final entry in entries) entry.part};
  final result = [
    for (final part in defaultMeasureParts)
      if (present.contains(part)) part,
  ];
  for (final part in present) {
    if (!result.contains(part)) result.add(part);
  }
  return result;
}

/// 运动汇总。
class WorkoutSummary {
  const WorkoutSummary({
    this.count = 0,
    this.minutes = 0,
    this.meters = 0,
    this.calories = 0,
  });

  final int count;
  final int minutes;
  final int meters;
  final int calories;
}

WorkoutSummary summarizeWorkouts(Iterable<WorkoutEntry> entries) {
  var count = 0;
  var minutes = 0;
  var meters = 0;
  var calories = 0;

  for (final entry in entries) {
    count++;
    minutes += entry.minutes;
    meters += entry.meters ?? 0;
    calories += entry.calories ?? 0;
  }
  return WorkoutSummary(
    count: count,
    minutes: minutes,
    meters: meters,
    calories: calories,
  );
}

/// 按运动类型汇总时长，降序排列。
List<({String type, int minutes})> minutesByType(
  Iterable<WorkoutEntry> entries,
) {
  final totals = <String, int>{};
  for (final entry in entries) {
    totals[entry.type] = (totals[entry.type] ?? 0) + entry.minutes;
  }
  final items = [
    for (final entry in totals.entries)
      (type: entry.key, minutes: entry.value),
  ];
  items.sort((a, b) => b.minutes.compareTo(a.minutes));
  return items;
}

/// 克 -> 展示用 kg 字符串。
String formatKg(int grams) => (grams / 1000).toStringAsFixed(2);

/// 用户输入的 kg -> 克。
int parseKgToGrams(String input) =>
    ((double.tryParse(input.trim()) ?? 0) * 1000).round();

/// 用户输入的 cm -> 毫米。
int parseCmToMm(String input) =>
    ((double.tryParse(input.trim()) ?? 0) * 10).round();

/// 用户输入的 km -> 米。
int parseKmToMeters(String input) =>
    ((double.tryParse(input.trim()) ?? 0) * 1000).round();

/// 毫米 -> 展示用 cm 字符串。
String formatCm(int mm) => (mm / 10).toStringAsFixed(1);

/// 米 -> 展示用 km 字符串（不足 1 公里时保留两位小数）。
String formatKm(int meters) => (meters / 1000).toStringAsFixed(2);

/// 分钟 -> 「1 小时 20 分」。
String formatDuration(int minutes) {
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分';
}
