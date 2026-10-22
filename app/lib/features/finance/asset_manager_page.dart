/// 资产管家：净资产汇总 + 按账户类型分组的余额列表。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_x.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import 'account_editor_page.dart';
import 'account_meta.dart';
import 'finance_providers.dart';

class AssetManagerPage extends ConsumerWidget {
  const AssetManagerPage({super.key});

  /// 分组顺序与命名。
  static const _groups = <AccountType, String>{
    AccountType.debitCard: '储蓄卡',
    AccountType.creditCard: '信用卡',
    AccountType.wechat: '虚拟账户',
    AccountType.alipay: '虚拟账户',
    AccountType.cash: '现金',
    AccountType.investment: '投资账户',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accounts =
        ref.watch(accountsProvider).dataOrNull ?? const <Account>[];
    final deltas =
        ref.watch(accountDeltasProvider).dataOrNull ?? const <String, int>{};

    final balances = <String, int>{
      for (final account in accounts)
        account.id: account.balanceInit + (deltas[account.id] ?? 0),
    };
    final net = balances.values.fold<int>(0, (sum, value) => sum + value);
    final assets = balances.values
        .where((value) => value > 0)
        .fold<int>(0, (sum, value) => sum + value);
    final liabilities = balances.values
        .where((value) => value < 0)
        .fold<int>(0, (sum, value) => sum + value.abs());

    // 同类型合并成一组（微信/支付宝都归「虚拟账户」）。
    final groupOrder = <String>[];
    final groupAccounts = <String, List<Account>>{};
    for (final account in accounts) {
      final group = _groups[account.type] ?? account.type.label;
      if (!groupAccounts.containsKey(group)) {
        groupOrder.add(group);
        groupAccounts[group] = [];
      }
      groupAccounts[group]!.add(account);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('资产管家'),
        actions: [
          IconButton(
            tooltip: '新增账户',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const AccountEditorPage()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _NetWorthCard(
            net: net,
            assets: assets,
            liabilities: liabilities,
          ),
          const SizedBox(height: 16),
          if (accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 48,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '还没有账户',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const AccountEditorPage(),
                      ),
                    ),
                    child: const Text('去添加账户'),
                  ),
                ],
              ),
            )
          else
            for (final group in groupOrder) ...[
              _GroupHeader(
                title: group,
                total: groupAccounts[group]!
                    .fold<int>(0, (sum, a) => sum + (balances[a.id] ?? 0)),
              ),
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    for (final account in groupAccounts[group]!)
                      _AccountRow(
                        account: account,
                        balance: balances[account.id] ?? 0,
                      ),
                  ],
                ),
              ),
            ],
          if (accounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '余额 = 初始余额 + 该账户的收入 − 支出',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
        ],
      ),
    );
  }
}

class _NetWorthCard extends StatelessWidget {
  const _NetWorthCard({
    required this.net,
    required this.assets,
    required this.liabilities,
  });

  final int net;
  final int assets;
  final int liabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF7CC6F2), Color(0xFF5BA8E8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -6,
            top: -26,
            child: Text(
              '¥',
              style: theme.textTheme.displayLarge?.copyWith(
                fontSize: 96,
                color: Colors.white.withValues(alpha: 0.18),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '净资产',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                formatCents(net),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _HeaderMetric(label: '资产', value: assets),
                  ),
                  Expanded(
                    child: _HeaderMetric(label: '负债', value: liabilities),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          formatCents(value),
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.total});

  final String title;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: theme.textTheme.titleSmall),
          ),
          Text(
            formatCents(total),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.balance});

  final Account account;
  final int balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accountColor(account.type);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(accountIcon(account.type), size: 20, color: color),
      ),
      title: Text(accountDisplayName(account)),
      subtitle: Text(
        account.type.label,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
      ),
      trailing: Text(
        formatCents(balance),
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: balance < 0 ? theme.colorScheme.error : null,
        ),
      ),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => AccountEditorPage(existing: account),
        ),
      ),
    );
  }
}
