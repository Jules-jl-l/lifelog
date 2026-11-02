/// 资产历史统计：按已有流水回溯每个周期末的净资产，并计算与上期的差值。
///
/// 口径：
/// - 净资产（t）= 当前净资产 − t 之后发生的收入 + t 之后发生的支出
/// - 转账不改变净资产，不计入变动
/// - 投资市值的手动调整没有历史时间点，会整体平移历史曲线，但不影响周期差值
library;

import '../core/period.dart';
import '../core/utils.dart';
import 'db/tables.dart';
import 'finance_assets.dart';

class AssetPeriodPoint {
  const AssetPeriodPoint({
    required this.option,
    required this.endNetWorth,
    required this.previousNetWorth,
    required this.changeCount,
  });

  final PeriodOption option;

  /// 周期末的回溯净资产。
  final int endNetWorth;

  /// 上一周期末的回溯净资产。
  final int previousNetWorth;

  /// 周期内发生了几笔收支（转账不计）。
  final int changeCount;

  int get change => endNetWorth - previousNetWorth;
}

/// 回溯 [at] 时刻的净资产。
int netWorthAt({
  required int currentNetWorth,
  required Iterable<AssetFlow> flows,
  required DateTime at,
}) {
  var value = currentNetWorth;
  for (final flow in flows) {
    final occurredAt = flow.occurredAt;
    if (occurredAt == null || !occurredAt.isAfter(at)) continue;
    // 未绑定账户的收支不影响账户余额，也就不构成资产变动
    if (flow.accountId == null || flow.accountId!.isEmpty) continue;
    switch (flow.kind) {
      case TxnKind.income:
        value -= flow.amount;
      case TxnKind.expense:
        value += flow.amount;
      case TxnKind.transfer:
        break;
    }
  }
  return value;
}

/// 生成周期条上每一段的历史变动；最后一项是当前周期。
List<AssetPeriodPoint> buildAssetHistory({
  required ViewPeriod period,
  required DateTime now,
  required int currentNetWorth,
  required Iterable<AssetFlow> flows,
}) {
  final options = periodOptions(period, now);
  final data = flows.toList();
  return [
    for (final option in options)
      _buildPoint(
        option: option,
        period: period,
        currentNetWorth: currentNetWorth,
        flows: data,
      ),
  ];
}

AssetPeriodPoint _buildPoint({
  required PeriodOption option,
  required ViewPeriod period,
  required int currentNetWorth,
  required List<AssetFlow> flows,
}) {
  final (_, end) = period.rangeOf(option.anchor);
  final endAt = endOfDay(end);
  final previousAnchor = switch (period) {
    ViewPeriod.week => option.anchor.subtract(const Duration(days: 7)),
    ViewPeriod.month => DateTime(option.anchor.year, option.anchor.month - 1),
    ViewPeriod.year => DateTime(option.anchor.year - 1),
  };
  final (_, previousEnd) = period.rangeOf(previousAnchor);
  final previousAt = endOfDay(previousEnd);

  var changeCount = 0;
  for (final flow in flows) {
    final occurredAt = flow.occurredAt;
    if (occurredAt == null || flow.kind == TxnKind.transfer) continue;
    if (flow.accountId == null || flow.accountId!.isEmpty) continue;
    if (occurredAt.isAfter(previousAt) && !occurredAt.isAfter(endAt)) {
      changeCount++;
    }
  }

  return AssetPeriodPoint(
    option: option,
    endNetWorth: netWorthAt(
      currentNetWorth: currentNetWorth,
      flows: flows,
      at: endAt,
    ),
    previousNetWorth: netWorthAt(
      currentNetWorth: currentNetWorth,
      flows: flows,
      at: previousAt,
    ),
    changeCount: changeCount,
  );
}
