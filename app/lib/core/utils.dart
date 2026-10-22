/// 通用工具：ID 生成、金额换算、时间处理。
///
/// 金额一律以「分」为单位存整数，避免浮点误差；展示时再换算成元。
library;

import 'dart:math';
import 'dart:typed_data';

/// RFC 9562 UUIDv7：前 48 位是毫秒时间戳，天然按时间有序。
String newId() {
  final ms = DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFFFFFF;
  final rand = Random.secure();
  final bytes = Uint8List(16);

  // 0-5 字节：48 位毫秒时间戳
  for (var i = 0; i < 6; i++) {
    bytes[i] = (ms >> (40 - i * 8)) & 0xFF;
  }

  // 6-15 字节：随机部分
  for (var i = 6; i < 16; i++) {
    bytes[i] = rand.nextInt(256);
  }

  // 版本位固定为 7
  bytes[6] = (bytes[6] & 0x0F) | 0x70;
  // 变体位固定为 10
  bytes[8] = (bytes[8] & 0x3F) | 0x80;

  final hex =
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// 分 -> 展示字符串（两位小数 + 千分位）。
String formatCents(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final yuan = abs ~/ 100;
  final fen = (abs % 100).toString().padLeft(2, '0');
  final grouped =
      yuan.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${negative ? '-' : ''}$grouped.$fen';
}

/// 用户输入的元 -> 分。
int parseYuanToCents(String input) {
  final value = double.tryParse(input.trim());
  if (value == null) return 0;
  return (value * 100).round();
}

/// 百分比展示。
String formatRatio(double ratio) => '${(ratio * 100).toStringAsFixed(1)}%';

/// 图表 X 轴桶标签：`YYYY-MM` 显示为「10月」，`YYYY-MM-DD` 显示为「10-21」。
///
/// 手机上横向空间有限，年度视图若显示完整年月会互相重叠。
String formatBucketLabel(String bucket) {
  if (bucket.length == 7 && bucket[4] == '-') {
    final month = int.tryParse(bucket.substring(5));
    return month == null ? bucket : '$month月';
  }
  if (bucket.length >= 10) return bucket.substring(5);
  return bucket;
}

DateTime startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// 当天最后一刻，用于区间查询的上界。
DateTime endOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day, 23, 59, 59, 999);

DateTime startOfMonth(DateTime value) => DateTime(value.year, value.month);

DateTime endOfMonth(DateTime value) => DateTime(value.year, value.month + 1, 0);

/// 统计周期。
enum StatsPeriod {
  day,
  month,
  year;

  /// 该周期的起止日期（含首尾）。
  (DateTime, DateTime) rangeOf(DateTime anchor) => switch (this) {
        StatsPeriod.day => (startOfDay(anchor), startOfDay(anchor)),
        StatsPeriod.month => (startOfMonth(anchor), endOfMonth(anchor)),
        StatsPeriod.year => (DateTime(anchor.year), DateTime(anchor.year, 12, 31)),
      };

  String get label => switch (this) {
        StatsPeriod.day => '日',
        StatsPeriod.month => '月',
        StatsPeriod.year => '年',
      };
}

/// 折线/趋势图的数据点：桶内没有记录时 [value] 为 null，折线断开。
class MetricPoint {
  const MetricPoint({required this.bucket, this.value});

  final String bucket;
  final double? value;
}

/// YYYY-MM，用于按月查询预算。
String monthKey(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}';

/// 该周期内每个小格子的键：日视图 = 当天、月视图 = 每天、年视图 = 每月。
List<String> bucketKeys(StatsPeriod period, DateTime anchor) {
  switch (period) {
    case StatsPeriod.day:
      return [formatDate(anchor)];
    case StatsPeriod.month:
      final start = startOfMonth(anchor);
      final days = endOfMonth(anchor).day;
      return List.generate(
        days,
        (index) => formatDate(DateTime(start.year, start.month, index + 1)),
      );
    case StatsPeriod.year:
      return List.generate(
        12,
        (index) => '${anchor.year}-${(index + 1).toString().padLeft(2, '0')}',
      );
  }
}

/// 把某个时间点归入对应周期的桶键。
String bucketKeyOf(DateTime local, StatsPeriod period) =>
    period == StatsPeriod.year
        ? '${local.year}-${local.month.toString().padLeft(2, '0')}'
        : formatDate(local);

String formatDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String formatDateTime(DateTime value) =>
    '${formatDate(value)} ${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';
