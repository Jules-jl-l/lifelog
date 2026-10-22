/// 财务统计计算的纯函数：不依赖数据库，便于单元测试。
///
/// 周期（周 / 月 / 年）与周期条逻辑统一放在 `core/period.dart`，财务与健康共用。
library;

import '../core/period.dart';
import 'db/tables.dart';

/// 参与统计的流水轻量结构。
class TxnEntry {
  const TxnEntry({
    required this.id,
    required this.kind,
    required this.amount,
    required this.occurredAt,
    this.categoryId,
  });

  final String id;
  final TxnKind kind;

  /// 分
  final int amount;
  final DateTime occurredAt;
  final String? categoryId;
}

class Summary {
  const Summary({required this.income, required this.expense, required this.count});

  final int income;
  final int expense;
  final int count;

  int get net => income - expense;
}

Summary summarize(Iterable<TxnEntry> entries) {
  var income = 0;
  var expense = 0;
  var count = 0;
  for (final entry in entries) {
    count++;
    switch (entry.kind) {
      case TxnKind.income:
        income += entry.amount;
      case TxnKind.expense:
        expense += entry.amount;
      case TxnKind.transfer:
        break;
    }
  }
  return Summary(income: income, expense: expense, count: count);
}

class BreakdownItem {
  const BreakdownItem({
    required this.categoryId,
    required this.amount,
    required this.ratio,
  });

  final String? categoryId;
  final int amount;
  final double ratio;
}

/// 按分类聚合，降序返回；占比基于同方向的总额。
List<BreakdownItem> breakdownByCategory(
  Iterable<TxnEntry> entries,
  TxnKind kind,
) {
  final totals = <String?, int>{};
  for (final entry in entries) {
    if (entry.kind != kind) continue;
    totals[entry.categoryId] = (totals[entry.categoryId] ?? 0) + entry.amount;
  }

  final grand = totals.values.fold<int>(0, (sum, value) => sum + value);
  final items = totals.entries
      .map((e) => BreakdownItem(
            categoryId: e.key,
            amount: e.value,
            ratio: grand == 0 ? 0 : e.value / grand,
          ))
      .toList();
  items.sort((a, b) => b.amount.compareTo(a.amount));
  return items;
}

class TrendPoint {
  const TrendPoint({required this.bucket, required this.income, required this.expense});

  final String bucket;
  final int income;
  final int expense;
}

/// 生成完整的时间轴（空档补 0），便于直接画趋势图。
List<TrendPoint> buildTrend(
  Iterable<TxnEntry> entries,
  ViewPeriod period,
  DateTime anchor,
) {
  final buckets = <String, (int, int)>{
    for (final key in periodBucketKeys(period, anchor)) key: (0, 0),
  };

  for (final entry in entries) {
    final key = periodBucketKeyOf(entry.occurredAt, period);
    final current = buckets[key];
    if (current == null) continue;
    buckets[key] = switch (entry.kind) {
      TxnKind.income => (current.$1 + entry.amount, current.$2),
      TxnKind.expense => (current.$1, current.$2 + entry.amount),
      TxnKind.transfer => current,
    };
  }

  return buckets.entries
      .map((e) => TrendPoint(bucket: e.key, income: e.value.$1, expense: e.value.$2))
      .toList();
}
