/// 流水明细：筛选 + 按日分组统计 + 列表 + 增删改。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_x.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import 'finance_providers.dart';
import 'transaction_editor.dart';

/// 一天的流水及其当日累计。
class _DayGroup {
  _DayGroup({required this.day, required this.rows});

  final DateTime day;
  final List<Transaction> rows;

  int get expense => rows
      .where((row) => row.kind == TxnKind.expense)
      .fold(0, (sum, row) => sum + row.amount);

  int get income => rows
      .where((row) => row.kind == TxnKind.income)
      .fold(0, (sum, row) => sum + row.amount);
}

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  final _payee = TextEditingController();
  final _note = TextEditingController();
  TxnKind? _kind;
  String? _accountId;
  DateTime? _from;
  DateTime? _to;

  @override
  void dispose() {
    _payee.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repository = ref.watch(financeRepositoryProvider);
    final categories = ref.watch(categoriesProvider).dataOrNull ??
        const <Category>[];
    final accounts =
        ref.watch(accountsProvider).dataOrNull ?? const <Account>[];
    final categoryNames = {for (final c in categories) c.id: c.name};
    final accountNames = {for (final a in accounts) a.id: a.name};
    final filtered = _hasFilters;

    return Scaffold(
      appBar: AppBar(
        title: const Text('流水明细'),
        actions: [
          if (filtered)
            IconButton(
              tooltip: '清除筛选',
              icon: const Icon(Icons.filter_alt_off_outlined),
              onPressed: _clearFilters,
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
            child: Row(
              children: [
                FilterChip(
                  label: const Text('支出'),
                  selected: _kind == TxnKind.expense,
                  onSelected: (selected) => setState(
                    () => _kind = selected ? TxnKind.expense : null,
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('收入'),
                  selected: _kind == TxnKind.income,
                  onSelected: (selected) => setState(
                    () => _kind = selected ? TxnKind.income : null,
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.filter_alt_outlined, size: 18),
                  label: Text(filtered ? '筛选 · 已启用' : '筛选'),
                  onPressed: _openFilters,
                ),
              ],
            ),
          ),
          if (filtered)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _filterSummary(accountNames),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<Transaction>>(
              stream: repository.watchTransactions(
                kind: _kind,
                accountId: _accountId,
                from: _from,
                to: _to == null ? null : endOfDay(_to!),
                payee: _payee.text,
                note: _note.text,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data ?? const <Transaction>[];
                if (rows.isEmpty) {
                  return const Center(child: Text('没有匹配的流水'));
                }
                final groups = _groupByDay(rows);
                return ListView.builder(
                  itemCount: groups.length,
                  itemBuilder: (context, index) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (index > 0) const _DaySeparator(),
                      _DayHeader(group: groups[index]),
                      for (final row in groups[index].rows)
                        _TransactionTile(
                          row: row,
                          accountNames: accountNames,
                          categoryNames: categoryNames,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasFilters =>
      _kind != null ||
      _accountId != null ||
      _from != null ||
      _to != null ||
      _payee.text.trim().isNotEmpty ||
      _note.text.trim().isNotEmpty;

  void _clearFilters() {
    setState(() {
      _kind = null;
      _accountId = null;
      _from = null;
      _to = null;
      _payee.clear();
      _note.clear();
    });
  }

  String _filterSummary(Map<String, String> accountNames) {
    final parts = <String>[
      if (_accountId != null) '账户 ${accountNames[_accountId] ?? '已删除账户'}',
      if (_payee.text.trim().isNotEmpty) '商户 ${_payee.text.trim()}',
      if (_note.text.trim().isNotEmpty) '备注 ${_note.text.trim()}',
      if (_from != null || _to != null) _dateLabel(),
    ];
    return parts.join(' · ');
  }

  String _dateLabel() {
    if (_from == null && _to == null) return '全部时间';
    return '${_from == null ? '起' : formatDate(_from!)}'
        ' ~ ${_to == null ? '今' : formatDate(_to!)}';
  }

  List<_DayGroup> _groupByDay(List<Transaction> rows) {
    final groups = <_DayGroup>[];
    for (final row in rows) {
      final day = startOfDay(row.occurredAt);
      final last = groups.isEmpty ? null : groups.last;
      if (last != null && formatDate(last.day) == formatDate(day)) {
        last.rows.add(row);
      } else {
        groups.add(_DayGroup(day: day, rows: [row]));
      }
    }
    return groups;
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _FilterSheet(
        accounts: ref.read(accountsProvider).dataOrNull ?? const <Account>[],
        accountId: _accountId,
        payee: _payee.text,
        note: _note.text,
        from: _from,
        to: _to,
      ),
    );
    if (result == null) return;
    setState(() {
      _accountId = result.accountId;
      _payee.text = result.payee;
      _note.text = result.note;
      _from = result.from;
      _to = result.to;
    });
  }
}

// ------------------------------------------------------------ 按日分组

class _DaySeparator extends StatelessWidget {
  const _DaySeparator();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 10,
      thickness: 10,
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.6),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.group});

  final _DayGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Text(
            formatMonthDayWeekday(group.day),
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  '支出 ¥${formatCents(group.expense)}'
                  '${group.income > 0 ? ' · 收入 ¥${formatCents(group.income)}' : ''}',
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.row,
    required this.accountNames,
    required this.categoryNames,
  });

  final Transaction row;
  final Map<String, String> accountNames;
  final Map<String, String> categoryNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIncome = row.kind == TxnKind.income;
    final isTransfer = row.kind == TxnKind.transfer;
    final toName = row.toAccountId == null
        ? null
        : (accountNames[row.toAccountId!] ?? '已删除账户');
    final accountName =
        row.accountId == null ? null : (accountNames[row.accountId] ?? '已删除账户');
    final note = row.note?.trim();
    // 时间已由按日分组表达，副标题改为备注；没有备注时退回账户名。
    final subtitleParts = <String>[
      if (note != null && note.isNotEmpty) note,
      ?accountName,
    ];

    return ListTile(
      title: Text(
        isTransfer
            ? '转账${toName == null ? '' : ' → $toName'}'
            : (row.payee?.isNotEmpty == true
                ? row.payee!
                : (row.categoryId == null
                    ? '未分类'
                    : (categoryNames[row.categoryId] ?? '已删除分类'))),
      ),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text(
              subtitleParts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 130),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            isTransfer
                ? '¥${formatCents(row.amount)}'
                : '${isIncome ? '+' : '-'}¥${formatCents(row.amount)}',
            maxLines: 1,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isTransfer
                  ? theme.colorScheme.outline
                  : isIncome
                      ? const Color(0xFF05994F)
                      : const Color(0xFFE8463A),
            ),
          ),
        ),
      ),
      onTap: () => openTransactionEditor(context, existing: row),
    );
  }
}

// ------------------------------------------------------------ 筛选弹层

class _FilterResult {
  const _FilterResult({
    this.accountId,
    this.payee = '',
    this.note = '',
    this.from,
    this.to,
  });

  final String? accountId;
  final String payee;
  final String note;
  final DateTime? from;
  final DateTime? to;
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.accounts,
    required this.accountId,
    required this.payee,
    required this.note,
    required this.from,
    required this.to,
  });

  final List<Account> accounts;
  final String? accountId;
  final String payee;
  final String note;
  final DateTime? from;
  final DateTime? to;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final TextEditingController _payee =
      TextEditingController(text: widget.payee);
  late final TextEditingController _note =
      TextEditingController(text: widget.note);
  late String? _accountId = widget.accountId;
  late DateTime? _from = widget.from;
  late DateTime? _to = widget.to;

  @override
  void dispose() {
    _payee.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('筛选流水', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _accountId,
              decoration: const InputDecoration(
                labelText: '账户',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(child: Text('全部账户')),
                for (final account in widget.accounts)
                  DropdownMenuItem<String?>(
                    value: account.id,
                    child: Text(account.name),
                  ),
              ],
              onChanged: (value) => setState(() => _accountId = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _payee,
              decoration: const InputDecoration(
                labelText: '商户',
                hintText: '按商户名筛选',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: '备注',
                hintText: '按备注内容筛选',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range, size: 18),
              label: Text(_dateLabel()),
              onPressed: _pickRange,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(
                      const _FilterResult(),
                    ),
                    child: const Text('重置'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      _FilterResult(
                        accountId: _accountId,
                        payee: _payee.text,
                        note: _note.text,
                        from: _from,
                        to: _to,
                      ),
                    ),
                    child: const Text('应用'),
                  ),
                ),
              ],
            ),
          ],
        ),
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
