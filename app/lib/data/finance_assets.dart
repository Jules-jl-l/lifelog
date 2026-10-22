/// 账户资产计算（纯函数）：
/// - 资产类余额 = 初始余额 + 收入 − 支出 + 转入 − 转出
/// - 投资类市值 = 本金 + 盈亏；本金 = 初始本金 + 转入 − 转出
/// - 负债类欠款 = 初始欠款 − 收入 + 支出 − 转入 + 转出
/// - 总资产 = 资产类余额 + 投资类市值；净资产 = 总资产 − 总负债
library;

import 'db/tables.dart';

/// 计算用的账户快照。
class AssetAccount {
  const AssetAccount({
    required this.id,
    required this.type,
    required this.balanceInit,
    this.marketAdjustment = 0,
  });

  final String id;
  final AccountType type;

  /// 资产类 / 投资类：初始余额或初始本金；负债类：初始欠款（允许旧数据为负数）。
  final int balanceInit;
  final int marketAdjustment;

  AccountClass get accountClass => type.accountClass;

  int get initialLiability => balanceInit.abs();
}

/// 计算用的流水快照（转账带转入账户）。
class AssetFlow {
  const AssetFlow({
    required this.kind,
    required this.amount,
    this.accountId,
    this.toAccountId,
  });

  final TxnKind kind;
  final int amount;
  final String? accountId;
  final String? toAccountId;
}

/// 单个账户的计算结果。
class AccountBalance {
  const AccountBalance({
    required this.id,
    required this.accountClass,
    required this.value,
    this.principal = 0,
    this.profit = 0,
  });

  final String id;
  final AccountClass accountClass;

  /// 资产类 = 可用余额；投资类 = 当前市值；负债类 = 欠款（正数）。
  final int value;

  /// 仅投资类：累计投入本金。
  final int principal;

  /// 仅投资类：盈亏 = 市值 − 本金。
  final int profit;
}

/// 三类汇总。
class AssetSummary {
  const AssetSummary({
    required this.accounts,
    required this.assetTotal,
    required this.investmentTotal,
    required this.liabilityTotal,
    required this.investmentPrincipal,
  });

  final Map<String, AccountBalance> accounts;
  final int assetTotal;
  final int investmentTotal;
  final int liabilityTotal;
  final int investmentPrincipal;

  /// 总资产 = 资产类 + 投资类市值。
  int get totalAssets => assetTotal + investmentTotal;

  /// 净资产 = 总资产 − 总负债。
  int get netWorth => totalAssets - liabilityTotal;

  /// 投资盈亏 = 投资类市值 − 累计投入本金。
  int get investmentProfit => investmentTotal - investmentPrincipal;

  int totalOf(AccountClass cls) => switch (cls) {
        AccountClass.asset => assetTotal,
        AccountClass.investment => investmentTotal,
        AccountClass.liability => liabilityTotal,
      };
}

AssetSummary summarizeAssets(
  Iterable<AssetAccount> accounts,
  Iterable<AssetFlow> flows,
) {
  final transferNet = <String, int>{};
  final nonTransferNet = <String, int>{};

  void addTransfer(String? id, int amount) {
    if (id == null || id.isEmpty) return;
    transferNet[id] = (transferNet[id] ?? 0) + amount;
  }

  for (final flow in flows) {
    switch (flow.kind) {
      case TxnKind.income:
        final id = flow.accountId;
        if (id != null && id.isNotEmpty) {
          nonTransferNet[id] = (nonTransferNet[id] ?? 0) + flow.amount;
        }
      case TxnKind.expense:
        final id = flow.accountId;
        if (id != null && id.isNotEmpty) {
          nonTransferNet[id] = (nonTransferNet[id] ?? 0) - flow.amount;
        }
      case TxnKind.transfer:
        addTransfer(flow.accountId, -flow.amount);
        addTransfer(flow.toAccountId, flow.amount);
    }
  }

  final balances = <String, AccountBalance>{};
  var assetTotal = 0;
  var investmentTotal = 0;
  var liabilityTotal = 0;
  var investmentPrincipal = 0;

  for (final account in accounts) {
    final transfer = transferNet[account.id] ?? 0;
    final nonTransfer = nonTransferNet[account.id] ?? 0;

    switch (account.accountClass) {
      case AccountClass.asset:
        final value = account.balanceInit + transfer + nonTransfer;
        assetTotal += value;
        balances[account.id] = AccountBalance(
          id: account.id,
          accountClass: AccountClass.asset,
          value: value,
        );
      case AccountClass.investment:
        final principal = account.balanceInit + transfer;
        final profit = nonTransfer + account.marketAdjustment;
        final value = principal + profit;
        investmentTotal += value;
        investmentPrincipal += principal;
        balances[account.id] = AccountBalance(
          id: account.id,
          accountClass: AccountClass.investment,
          value: value,
          principal: principal,
          profit: profit,
        );
      case AccountClass.liability:
        final owed =
            account.initialLiability - transfer - nonTransfer;
        final value = owed < 0 ? 0 : owed;
        liabilityTotal += value;
        balances[account.id] = AccountBalance(
          id: account.id,
          accountClass: AccountClass.liability,
          value: value,
        );
    }
  }

  return AssetSummary(
    accounts: balances,
    assetTotal: assetTotal,
    investmentTotal: investmentTotal,
    liabilityTotal: liabilityTotal,
    investmentPrincipal: investmentPrincipal,
  );
}
