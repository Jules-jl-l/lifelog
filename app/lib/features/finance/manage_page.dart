/// 账户 / 分类 / 预算 的集中管理页。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_x.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/finance_stats.dart';
import '../../data/providers.dart';
import 'account_editor_page.dart';
import 'account_meta.dart';
import 'category_editor_page.dart';
import 'finance_providers.dart';

class ManagePage extends StatefulWidget {
  const ManagePage({super.key});

  @override
  State<ManagePage> createState() => _ManagePageState();
}

class _ManagePageState extends State<ManagePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('账户与分类'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: '账户'), Tab(text: '分类'), Tab(text: '预算')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_AccountsTab(), _CategoriesTab(), _BudgetsTab()],
      ),
    );
  }
}

// ------------------------------------------------------------ 账户

class _AccountsTab extends ConsumerWidget {
  const _AccountsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);

    return Column(
      children: [
        _TabHeader(
          title: '账户',
          onAdd: () => _editAccount(context, ref),
        ),
        Expanded(
          child: accountsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('加载失败：$error')),
            data: (accounts) {
              if (accounts.isEmpty) {
                return const Center(child: Text('还没有账户，先建一个（如：微信、储蓄卡）'));
              }
              return ListView.separated(
                itemCount: accounts.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final account = accounts[index];
                  return ListTile(
                    title: Text(account.name),
                    subtitle: Text(
                      '${accountTypeLabel(account)}'
                      '${account.cardLast4 == null ? '' : ' · 尾号 ${account.cardLast4}'}'
                      ' · ${switch (account.type.accountClass) {
                        AccountClass.asset => '初始余额',
                        AccountClass.investment => '本金',
                        AccountClass.liability => '欠款',
                      }} ¥${formatCents(account.type.accountClass == AccountClass.liability ? account.balanceInit.abs() : account.balanceInit)}',
                    ),
                    onTap: () => _editAccount(context, ref, account: account),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          ref.read(financeRepositoryProvider).deleteAccount(account.id),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _editAccount(
    BuildContext context,
    WidgetRef ref, {
    Account? account,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AccountEditorPage(existing: account),
      ),
    );
  }
}

// ------------------------------------------------------------ 分类

class _CategoriesTab extends ConsumerWidget {
  const _CategoriesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Column(
      children: [
        _TabHeader(title: '分类', onAdd: () => _editCategory(context, ref)),
        Expanded(
          child: categoriesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('加载失败：$error')),
            data: (categories) {
              if (categories.isEmpty) {
                return const Center(child: Text('还没有分类，先建几个（如：餐饮、交通、工资）'));
              }
              return ListView.separated(
                itemCount: categories.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  return ListTile(
                    title: Text(category.name),
                    subtitle: Text(category.kind.label),
                    onTap: () => _editCategory(context, ref, category: category),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => ref
                          .read(financeRepositoryProvider)
                          .deleteCategory(category.id),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _editCategory(
    BuildContext context,
    WidgetRef ref, {
    Category? category,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CategoryEditorPage(existing: category),
      ),
    );
  }
}

// ------------------------------------------------------------ 预算

class _BudgetsTab extends ConsumerStatefulWidget {
  const _BudgetsTab();

  @override
  ConsumerState<_BudgetsTab> createState() => _BudgetsTabState();
}

class _BudgetsTabState extends ConsumerState<_BudgetsTab> {
  DateTime _month = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final period = monthKey(_month);
    final (start, end) = StatsPeriod.month.rangeOf(_month);
    final budgetsAsync = ref.watch(budgetsProvider(period));
    final entries = ref
            .watch(entriesProvider((start: start, end: end)))
            .dataOrNull ??
        const <TxnEntry>[];
    final categoryNames =
        <String, String>{
          for (final item
              in ref.watch(categoriesProvider).dataOrNull ?? const <Category>[])
            item.id: item.name,
        };
    final breakdown = breakdownByCategory(entries, TxnKind.expense);
    final spendByCategory = {
      for (final item in breakdown)
        if (item.categoryId != null) item.categoryId!: item.amount,
    };
    final totalExpense =
        breakdown.fold<int>(0, (sum, item) => sum + item.amount);

    return Column(
      children: [
        _TabHeader(
          title: '预算 · ${monthKey(_month)}',
          onAdd: () =>
              _editBudget(context, ref, period, categoryNames.keys.toList()),
          leading: IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _month,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _month = picked);
            },
          ),
        ),
        Expanded(
          child: budgetsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('加载失败：$error')),
            data: (budgets) {
              if (budgets.isEmpty) {
                return const Center(child: Text('本月还没有预算，可先设一个总预算'));
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: budgets.length,
                itemBuilder: (context, index) {
                  final budget = budgets[index];
                  final used = budget.categoryId == null
                      ? totalExpense
                      : (spendByCategory[budget.categoryId] ?? 0);
                  final ratio =
                      budget.amount == 0 ? 0.0 : used / budget.amount;
                  final label = budget.categoryId == null
                      ? '总预算'
                      : (categoryNames[budget.categoryId] ?? '已删除分类');

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  label,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              Text(
                                '¥${formatCents(used)} / ¥${formatCents(budget.amount)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline,
                                    ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => ref
                                    .read(financeRepositoryProvider)
                                    .deleteBudget(budget.id),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: ratio.clamp(0, 1),
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                            color: ratio > 1
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            ratio > 1
                                ? '已超支 ${formatRatio(ratio)}'
                                : '已用 ${formatRatio(ratio)}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: ratio > 1
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _editBudget(
    BuildContext context,
    WidgetRef ref,
    String period,
    List<String> categoryIds,
  ) async {
    final amountController = TextEditingController();
    String? categoryId;

    final categories =
        ref.read(categoriesProvider).dataOrNull ?? const <Category>[];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('设置 $period 预算'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('总预算'),
                      selected: categoryId == null,
                      onSelected: (_) => setDialogState(() => categoryId = null),
                    ),
                    for (final category in categories)
                      if (category.kind == TxnKind.expense)
                        ChoiceChip(
                          label: Text(category.name),
                          selected: categoryId == category.id,
                          onSelected: (_) =>
                              setDialogState(() => categoryId = category.id),
                        ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: '预算金额',
                    prefixText: '¥ ',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final amount = parseYuanToCents(amountController.text);
                if (amount <= 0) return;
                await ref.read(financeRepositoryProvider).saveBudget(
                      period: period,
                      categoryId: categoryId,
                      amount: amount,
                    );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ 公共

class _TabHeader extends StatelessWidget {
  const _TabHeader({required this.title, required this.onAdd, this.leading});

  final String title;
  final VoidCallback onAdd;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          ?leading,
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新增'),
          ),
        ],
      ),
    );
  }
}
