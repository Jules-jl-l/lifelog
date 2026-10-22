/// 流水明细：筛选 + 列表 + 增删改。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_x.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import 'finance_providers.dart';
import 'transaction_editor.dart';

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  final _keyword = TextEditingController();
  TxnKind? _kind;
  DateTime? _from;
  DateTime? _to;

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(financeRepositoryProvider);
    final categories = ref.watch(categoriesProvider).dataOrNull ??
        const <Category>[];
    final accounts =
        ref.watch(accountsProvider).dataOrNull ?? const <Account>[];
    final categoryNames = {for (final c in categories) c.id: c.name};
    final accountNames = {for (final a in accounts) a.id: a.name};

    return Scaffold(
      appBar: AppBar(
        title: const Text('流水明细'),
        actions: [
          IconButton(
            tooltip: '清除筛选',
            icon: const Icon(Icons.filter_alt_off_outlined),
            onPressed: () => setState(() {
              _kind = null;
              _from = null;
              _to = null;
              _keyword.clear();
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => openTransactionEditor(context),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _keyword,
                  decoration: const InputDecoration(
                    hintText: '搜索商户或备注',
                    prefixIcon: Icon(Icons.search),
                    suffixIcon: Icon(Icons.close),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('支出'),
                            selected: _kind == TxnKind.expense,
                            onSelected: (selected) => setState(
                              () => _kind = selected ? TxnKind.expense : null,
                            ),
                          ),
                          FilterChip(
                            label: const Text('收入'),
                            selected: _kind == TxnKind.income,
                            onSelected: (selected) => setState(
                              () => _kind = selected ? TxnKind.income : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text(_dateLabel()),
                      onPressed: _pickRange,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<Transaction>>(
              stream: repository.watchTransactions(
                kind: _kind,
                from: _from,
                to: _to,
                keyword: _keyword.text,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data ?? const <Transaction>[];
                if (rows.isEmpty) {
                  return const Center(child: Text('没有匹配的流水'));
                }
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final isIncome = row.kind == TxnKind.income;
                    final isTransfer = row.kind == TxnKind.transfer;
                    final toName = row.toAccountId == null
                        ? null
                        : (accountNames[row.toAccountId!] ?? '已删除账户');
                    return ListTile(
                      title: Text(
                        isTransfer
                            ? '转账${toName == null ? '' : ' → $toName'}'
                            : (row.payee?.isNotEmpty == true
                                ? row.payee!
                                : (row.categoryId == null
                                    ? '未分类'
                                    : (categoryNames[row.categoryId] ??
                                        '已删除分类'))),
                      ),
                      subtitle: Text(
                        '${formatDateTime(row.occurredAt)}'
                        '${row.accountId == null ? '' : ' · ${accountNames[row.accountId] ?? '已删除账户'}'}',
                      ),
                      trailing: Text(
                        isTransfer
                            ? '¥${formatCents(row.amount)}'
                            : '${isIncome ? '+' : '-'}¥${formatCents(row.amount)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isTransfer
                              ? Theme.of(context).colorScheme.outline
                              : isIncome
                                  ? const Color(0xFF05994F)
                                  : const Color(0xFFE8463A),
                        ),
                      ),
                      onTap: () =>
                          openTransactionEditor(context, existing: row),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _dateLabel() {
    if (_from == null && _to == null) return '全部时间';
    return '${_from == null ? '起' : formatDate(_from!)}'
        ' ~ ${_to == null ? '今' : formatDate(_to!)}';
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _from != null && _to != null
          ? DateTimeRange(start: _from!, end: _to!)
          : null,
    );
    if (range != null) {
      setState(() {
        _from = range.start;
        _to = range.end;
      });
    }
  }
}
