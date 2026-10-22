/// 资产管家：资产 / 投资 / 负债三类汇总 + 净资产。
///
/// 口径：
/// - 总资产 = 资产类余额 + 投资类当前市值
/// - 总负债 = 负债类欠款合计
/// - 净资产 = 总资产 − 总负债
/// - 投资盈亏 = 投资类市值 − 累计投入本金
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_x.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/finance_assets.dart';
import '../../data/providers.dart';
import 'account_editor_page.dart';
import 'account_meta.dart';
import 'finance_providers.dart';

class AssetManagerPage extends ConsumerWidget {
  const AssetManagerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accounts =
        ref.watch(accountsProvider).dataOrNull ?? const <Account>[];
    final flows =
        ref.watch(assetFlowsProvider).dataOrNull ?? const <AssetFlow>[];

    final summary = summarizeAssets(
      [
        for (final account in accounts)
          AssetAccount(
            id: account.id,
            type: account.type,
            balanceInit: account.balanceInit,
            marketAdjustment: account.marketAdjustment,
          ),
      ],
      flows,
    );

    final groups = <AccountClass, List<Account>>{
      for (final cls in AccountClass.values) cls: [],
    };
    for (final account in accounts) {
      groups[account.type.accountClass]!.add(account);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('资产管家'),
        actions: [
          IconButton(
            tooltip: '新增账户',
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _NetWorthCard(summary: summary),
          const SizedBox(height: 18),
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
                    onPressed: () => _openEditor(context),
                    child: const Text('去添加账户'),
                  ),
                ],
              ),
            )
          else
            for (final cls in AccountClass.values)
              if (groups[cls]!.isNotEmpty) ...[
                _GroupHeader(
                  accountClass: cls,
                  total: summary.totalOf(cls),
                  profit: cls == AccountClass.investment
                      ? summary.investmentProfit
                      : null,
                ),
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    children: [
                      for (final account in groups[cls]!)
                        _AccountRow(
                          account: account,
                          balance: summary.accounts[account.id],
                          onEditMarket: account.type.accountClass ==
                                  AccountClass.investment
                              ? () => _editMarketValue(context, ref, account)
                              : null,
                        ),
                    ],
                  ),
                ),
              ],
          if (accounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '资产类按余额、投资类按市值计入总资产；负债类欠款计入总负债。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openEditor(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const AccountEditorPage()),
    );
  }

  Future<void> _editMarketValue(
    BuildContext context,
    WidgetRef ref,
    Account account,
  ) async {
    final repository = ref.read(financeRepositoryProvider);
    final principal = await repository.investmentPrincipalOnce(account.id);
    if (!context.mounted) return;
    final current = principal + account.marketAdjustment;

    final controller = TextEditingController(
      text: (current / 100).toStringAsFixed(2),
    );
    final cents = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('更新市值'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '累计本金 ${formatCents(principal)}',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              decoration: const InputDecoration(
                labelText: '当前市值',
                prefixText: '¥ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              parseYuanToCents(controller.text),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (cents == null) return;

    await repository.saveAccount(
      id: account.id,
      name: account.name,
      type: account.type,
      balanceInit: account.balanceInit,
      customType: account.customLabel,
      marketAdjustment: cents - principal,
      cardFirst4: account.cardFirst4,
      cardLast4: account.cardLast4,
      sort: account.sort,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已更新「${account.name}」市值')),
    );
  }
}

class _NetWorthCard extends StatelessWidget {
  const _NetWorthCard({required this.summary});

  final AssetSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profit = summary.investmentProfit;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
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
                formatCents(summary.netWorth),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _HeaderMetric(
                      label: '总资产',
                      value: formatCents(summary.totalAssets),
                    ),
                  ),
                  Expanded(
                    child: _HeaderMetric(
                      label: '总负债',
                      value: formatCents(summary.liabilityTotal),
                    ),
                  ),
                  Expanded(
                    child: _HeaderMetric(
                      label: '投资盈亏',
                      value:
                          '${profit >= 0 ? '+' : ''}${formatCents(profit)}',
                    ),
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
  final String value;

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
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.accountClass,
    required this.total,
    this.profit,
  });

  final AccountClass accountClass;
  final int total;
  final int? profit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(accountClass.label, style: theme.textTheme.titleSmall),
          ),
          Text(
            formatCents(total),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          if (profit != null) ...[
            const SizedBox(width: 8),
            Text(
              '盈亏 ${profit! >= 0 ? '+' : ''}${formatCents(profit!)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: profit! < 0
                    ? theme.colorScheme.error
                    : const Color(0xFF2E9E62),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.balance,
    this.onEditMarket,
  });

  final Account account;
  final AccountBalance? balance;
  final VoidCallback? onEditMarket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accountColor(account.type);
    final value = balance?.value ?? 0;
    final liability = account.type.accountClass == AccountClass.liability;
    final investment =
        account.type.accountClass == AccountClass.investment;
    final profit = balance?.profit ?? 0;

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
        investment
            ? '${accountTypeLabel(account)} · 本金 ${formatCents(balance?.principal ?? 0)}'
            : accountTypeLabel(account),
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                liability ? '-${formatCents(value)}' : formatCents(value),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: liability ? theme.colorScheme.error : null,
                ),
              ),
              if (investment)
                Text(
                  '${profit >= 0 ? '+' : ''}${formatCents(profit)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: profit < 0
                        ? theme.colorScheme.error
                        : const Color(0xFF2E9E62),
                  ),
                ),
            ],
          ),
          if (onEditMarket != null)
            IconButton(
              tooltip: '更新市值',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: onEditMarket,
            ),
        ],
      ),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => AccountEditorPage(existing: account),
        ),
      ),
    );
  }
}
