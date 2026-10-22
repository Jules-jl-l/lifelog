/// 新建 / 编辑账户页面。
///
/// 银行卡类账户需要填写卡号后四位（必填）与前四位（选填），
/// 只保存前后各四位，不保存完整卡号。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';

class AccountEditorPage extends ConsumerStatefulWidget {
  const AccountEditorPage({super.key, this.existing});

  final Account? existing;

  @override
  ConsumerState<AccountEditorPage> createState() => _AccountEditorPageState();
}

class _AccountEditorPageState extends ConsumerState<AccountEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _balance;
  late final TextEditingController _first4;
  late final TextEditingController _last4;
  late AccountType _type;
  bool _saving = false;

  bool get _isCard =>
      _type == AccountType.debitCard || _type == AccountType.creditCard;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _balance = TextEditingController(
      text: existing == null
          ? '0'
          : (existing.balanceInit / 100).toStringAsFixed(2),
    );
    _first4 = TextEditingController(text: existing?.cardFirst4 ?? '');
    _last4 = TextEditingController(text: existing?.cardLast4 ?? '');
    _type = existing?.type ?? AccountType.debitCard;
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    _first4.dispose();
    _last4.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _notify('请填写账户名称');
      return;
    }

    final first4 = _first4.text.trim();
    final last4 = _last4.text.trim();
    if (_isCard) {
      if (last4.length != 4) {
        _notify('请填写卡号后四位（4 位数字）');
        return;
      }
      if (first4.isNotEmpty && first4.length != 4) {
        _notify('卡号前四位需要填满 4 位，或留空');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final id = await ref.read(financeRepositoryProvider).saveAccount(
            id: widget.existing?.id,
            name: name,
            type: _type,
            balanceInit: parseYuanToCents(_balance.text),
            cardFirst4: _isCard && first4.isNotEmpty ? first4 : null,
            cardLast4: _isCard ? last4 : null,
            sort: widget.existing?.sort ?? 0,
          );
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _notify('保存失败：$error');
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? '编辑账户' : '新建账户')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          TextField(
            controller: _name,
            autofocus: !_editing,
            decoration: const InputDecoration(
              labelText: '账户名称',
              hintText: '例如：招商银行、微信',
            ),
          ),
          const SizedBox(height: 20),
          Text('账户类型', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in AccountType.values)
                ChoiceChip(
                  label: Text(option.label),
                  selected: _type == option,
                  onSelected: (_) => setState(() => _type = option),
                ),
            ],
          ),
          if (_isCard) ...[
            const SizedBox(height: 20),
            Text('银行卡号', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              '只保存前后各四位，不保存完整卡号',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _first4,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: const InputDecoration(
                      labelText: '前四位',
                      hintText: '6225（选填）',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text('····', style: theme.textTheme.titleMedium),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _last4,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: const InputDecoration(
                      labelText: '后四位',
                      hintText: '0137（必填）',
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _balance,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
            ],
            decoration: const InputDecoration(
              labelText: '初始余额',
              prefixText: '¥ ',
              hintText: '信用卡欠款可填负数',
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving ? '保存中…' : (_editing ? '保存' : '创建'),
            ),
          ),
        ],
      ),
    );
  }
}
