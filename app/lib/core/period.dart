/// 周 / 月 / 年统计周期：财务与健康共用同一套区间与周期条逻辑。
///
/// 学习模块仍使用 [StatsPeriod]（日 / 月 / 年），两者互不影响。
library;

import 'utils.dart';

/// 统计周期：周（周一为起点）/ 月 / 年。
enum ViewPeriod {
  week,
  month,
  year;

  /// 该周期的起止日期（含首尾；月的结束日为当天零点，
  /// 查询层会统一用 [endOfDay] 归一）。
  (DateTime, DateTime) rangeOf(DateTime anchor) => switch (this) {
        ViewPeriod.week => (
            startOfWeek(anchor),
            endOfDay(startOfWeek(anchor).add(const Duration(days: 6))),
          ),
        ViewPeriod.month => (startOfMonth(anchor), endOfMonth(anchor)),
        ViewPeriod.year => (
            DateTime(anchor.year),
            endOfDay(DateTime(anchor.year, 12, 31)),
          ),
      };

  String get label => switch (this) {
        ViewPeriod.week => '周',
        ViewPeriod.month => '月',
        ViewPeriod.year => '年',
      };
}

/// 周一作为一周第一天。
DateTime startOfWeek(DateTime value) {
  final day = startOfDay(value);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// ISO-8601 周序号（跨年周归属按周四所在年份计算）。
int isoWeekNumber(DateTime value) {
  final date = DateTime.utc(value.year, value.month, value.day);
  final thursday = date.add(Duration(days: 4 - date.weekday));
  final firstThursday = DateTime.utc(thursday.year, 1, 4);
  final firstWeekThursday =
      firstThursday.add(Duration(days: 4 - firstThursday.weekday));
  return 1 + thursday.difference(firstWeekThursday).inDays ~/ 7;
}

/// 趋势图的桶键：周 / 月按天，年按月。
List<String> periodBucketKeys(ViewPeriod period, DateTime anchor) {
  switch (period) {
    case ViewPeriod.week:
      final start = startOfWeek(anchor);
      return List.generate(
        7,
        (index) => formatDate(start.add(Duration(days: index))),
      );
    case ViewPeriod.month:
      final start = startOfMonth(anchor);
      final days = endOfMonth(anchor).day;
      return List.generate(
        days,
        (index) => formatDate(DateTime(start.year, start.month, index + 1)),
      );
    case ViewPeriod.year:
      return List.generate(
        12,
        (index) => '${anchor.year}-${(index + 1).toString().padLeft(2, '0')}',
      );
  }
}

String periodBucketKeyOf(DateTime local, ViewPeriod period) =>
    period == ViewPeriod.year
        ? '${local.year}-${local.month.toString().padLeft(2, '0')}'
        : formatDate(local);

/// 周期条上的一个可选项。
class PeriodOption {
  const PeriodOption({
    required this.key,
    required this.label,
    required this.anchor,
  });

  final String key;
  final String label;
  final DateTime anchor;
}

/// 生成周期条：最近的 26 周 / 24 个月 / 10 年，最后一项对应当前周期。
List<PeriodOption> periodOptions(ViewPeriod period, DateTime now) {
  switch (period) {
    case ViewPeriod.week:
      final current = startOfWeek(now);
      return [
        for (var offset = 25; offset >= 0; offset--)
          PeriodOption(
            key: 'w-${formatDate(current.subtract(Duration(days: offset * 7)))}',
            label: switch (offset) {
              0 => '本周',
              1 => '上周',
              _ => '${isoWeekNumber(current.subtract(Duration(days: offset * 7)))}周',
            },
            anchor: current.subtract(Duration(days: offset * 7)),
          ),
      ];
    case ViewPeriod.month:
      final months = <PeriodOption>[];
      for (var offset = 23; offset >= 0; offset--) {
        final month = DateTime(now.year, now.month - offset);
        months.add(
          PeriodOption(
            key: 'm-${monthKey(month)}',
            label: switch (offset) {
              0 => '本月',
              1 => '上月',
              _ => month.year == now.year
                  ? '${month.month}月'
                  : '${month.year % 100}年${month.month}月',
            },
            anchor: month,
          ),
        );
      }
      return months;
    case ViewPeriod.year:
      return [
        for (var offset = 9; offset >= 0; offset--)
          PeriodOption(
            key: 'y-${now.year - offset}',
            label: switch (offset) {
              0 => '今年',
              1 => '去年',
              _ => '${now.year - offset}年',
            },
            anchor: DateTime(now.year - offset),
          ),
      ];
  }
}

/// 区间提示文案：周显示起止日，月 / 年显示中文区间。
String periodRangeHint(ViewPeriod period, DateTime start, DateTime end) =>
    switch (period) {
      ViewPeriod.week =>
        '${formatDate(start).substring(5)} ~ ${formatDate(end).substring(5)}',
      ViewPeriod.month => '${start.year} 年 ${start.month} 月',
      ViewPeriod.year => '${start.year} 年',
    };
