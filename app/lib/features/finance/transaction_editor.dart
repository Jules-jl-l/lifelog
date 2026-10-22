/// 记账编辑器：底部弹层，支持新增与修改。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_x.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import 'account_editor_page.dart';
import 'account_meta.dart';
import 'category_editor_page.dart';
import 'finance_providers.dart';

Future<void> openTransactionEditor(
  BuildContext context, {
  Transaction? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => TransactionEditor(existing: existing),
  );
}

class TransactionEditor extends ConsumerStatefulWidget {
  const TransactionEditor({super.key, this.existing});

  final Transaction? existing;

  @override
  ConsumerState<TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends ConsumerState<TransactionEditor> {
  late TxnKind _kind;
  late final TextEditingController _amount;
  late final TextEditingController _payee;
  late final TextEditingController _note;
  late DateTime _occurredAt;
  String? _categoryId;
  String? _accountId;
  String? _toAccountId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _kind = existing?.kind ?? TxnKind.expense;
    _amount = TextEditingController(
      text: existing == null ? '' : (existing.amount / 100).toStringAsFixed(2),
    );
    _payee = TextEditingController(text: existing?.payee ?? '');
    _note = TextEditingController(text: existing?.note ?? '');
    _occurredAt = existing?.occurredAt ?? DateTime.now();
    _categoryId = existing?.categoryId;
    _accountId = existing?.accountId;
    _toAccountId = existing?.toAccountId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoriesProvider).dataOrNull ??
        const <Category>[];
    final accounts =
        ref.watch(accountsProvider).dataOrNull ?? const <Account>[];
    final kindCategories =
        categories.where((item) => item.kind == _kind).toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  widget.existing == null ? '记一笔' : '编辑流水',
                  style: theme.textTheme.titleLarge,
                ),
                const Spacer(),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                if (widget.existing != null)
                  TextButton.icon(
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('删除'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<TxnKind>(
              segments: const [
                ButtonSegment(value: TxnKind.expense, label: Text('支出')),
                ButtonSegment(value: TxnKind.income, label: Text('收入')),
                ButtonSegment(value: TxnKind.transfer, label: Text('转账')),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (values) => setState(() {
                _kind = values.first;
                _categoryId = null;
                if (_kind != TxnKind.transfer) _toAccountId = null;
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: theme.textTheme.headlineSmall,
              decoration: const InputDecoration(
                labelText: '金额',
                prefixText: '¥ ',
                hintText: '0.00',
              ),
            ),
            const SizedBox(height: 20),
            if (_kind != TxnKind.transfer) ...[
              Row(
                children: [
                  Text('分类', style: theme.textTheme.labelLarge),
                  IconButton(
                    tooltip: '新增分类',
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    onPressed: _saving ? null : _createCategory,
                    icon: const Icon(Icons.add, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (kindCategories.isEmpty)
                Text(
                  '还没有${_kind.label}分类，点上方 + 新建',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in kindCategories)
                      ChoiceChip(
                        label: Text(item.name),
                        selected: _categoryId == item.id,
                        onSelected: (_) => setState(() => _categoryId = item.id),
                      ),
                  ],
                ),
              const SizedBox(height: 20),
            ],
            Row(
              children: [
                Text(
                  _kind == TxnKind.transfer ? '转出账户' : '账户',
                  style: theme.textTheme.labelLarge,
                ),
                IconButton(
                  tooltip: '新增账户',
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  onPressed: _saving ? null : _createAccount,
                  icon: const Icon(Icons.add, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (accounts.isEmpty)
              Text(
                '还没有账户，点上方 + 新建',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in accounts)
                    ChoiceChip(
                      label: Text(accountDisplayName(item)),
                      selected: _accountId == item.id,
                      onSelected: (_) => setState(() => _accountId = item.id),
                    ),
                ],
              ),
            if (_kind == TxnKind.transfer) ...[
              const SizedBox(height: 16),
              Text('转入账户', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              if (accounts.length < 2)
                Text(
                  '至少需要两个账户才能转账',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in accounts)
                      ChoiceChip(
                        label: Text(accountDisplayName(item)),
                        selected: _toAccountId == item.id,
                        onSelected: (_) =>
                            setState(() => _toAccountId = item.id),
                      ),
                  ],
                ),
            ],
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('时间'),
              subtitle: Text(formatDateTime(_occurredAt)),
              onTap: _pickDateTime,
            ),
            TextField(
              controller: _payee,
              decoration: const InputDecoration(
                labelText: '商户 / 对方',
                hintText: '例如：食堂、地铁',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '备注'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中…' : '保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (!mounted) return;

    setState(() {
      _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _occurredAt.hour,
        time?.minute ?? _occurredAt.minute,
      );
    });
  }

  Future<void> _save() async {
    final cents = parseYuanToCents(_amount.text);
    if (cents <= 0) {
      _notify('请输入大于 0 的金额');
      return;
    }
    if (_kind == TxnKind.transfer) {
      if (_accountId == null || _toAccountId == null) {
        _notify('请选择转出账户和转入账户');
        return;
      }
      if (_accountId == _toAccountId) {
        _notify('转出和转入账户不能相同');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await ref.read(financeRepositoryProvider).saveTransaction(
            id: widget.existing?.id,
            kind: _kind,
            amount: cents,
            occurredAt: _occurredAt,
            categoryId: _categoryId,
            accountId: _accountId,
            toAccountId: _kind == TxnKind.transfer ? _toAccountId : null,
            payee: _payee.text.trim().isEmpty ? null : _payee.text.trim(),
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _notify('保存失败：$error');
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(financeRepositoryProvider).deleteTransaction(id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _notify('删除失败：$error');
    }
  }

  /// 空库时也能就地新建分类：跳到独立页面，返回后自动选中。
  Future<void> _createCategory() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CategoryEditorPage(initialKind: _kind),
      ),
    );
    if (id == null || !mounted) return;
    setState(() => _categoryId = id);
  }

  /// 空库时也能就地新建账户：跳到独立页面，返回后自动选中。
  Future<void> _createAccount() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AccountEditorPage()),
    );
    if (id == null || !mounted) return;
    setState(() => _accountId = id);
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
