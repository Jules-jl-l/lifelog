/// 新建 / 编辑账户页面。
///
/// 账户分三大类：资产类（按余额计入总资产）、投资类（按市值计入总资产）、
/// 负债类（计入总负债）。银行卡类账户只保存卡号前后各四位。
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
  late final TextEditingController _marketValue;
  late final TextEditingController _customType;
  late final TextEditingController _first4;
  late final TextEditingController _last4;
  late AccountClass _accountClass;
  late AccountType _type;

  /// 编辑投资账户时，从流水算出累计投入本金后回填当前市值。
  int? _principal;
  bool _saving = false;

  bool get _editing => widget.existing != null;

  bool get _isCard => _type.isCardType;

  bool get _isInvestment => _accountClass == AccountClass.investment;

  bool get _isLiability => _accountClass == AccountClass.liability;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _customType = TextEditingController(text: existing?.customLabel ?? '');
    _balance = TextEditingController(
      text: existing == null ? '0' : _initialAmount(existing),
    );
    _marketValue = TextEditingController();
    _first4 = TextEditingController(text: existing?.cardFirst4 ?? '');
    _last4 = TextEditingController(text: existing?.cardLast4 ?? '');
    _accountClass = existing?.type.accountClass ?? AccountClass.asset;
    _type = existing?.type ?? AccountType.debitCard;

    if (existing != null && _isInvestment) {
      _loadInvestmentValue(existing);
    }
  }

  String _initialAmount(Account account) {
    final cents = account.type.accountClass == AccountClass.liability
        ? account.balanceInit.abs()
        : account.balanceInit;
    return (cents / 100).toStringAsFixed(2);
  }

  Future<void> _loadInvestmentValue(Account account) async {
    final principal =
        await ref.read(financeRepositoryProvider).investmentPrincipalOnce(
              account.id,
            );
    if (!mounted) return;
    setState(() {
      _principal = principal;
      _marketValue.text =
          ((principal + account.marketAdjustment) / 100).toStringAsFixed(2);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    _marketValue.dispose();
    _customType.dispose();
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

    final custom = _customType.text.trim();
    if (_type.isCustom && custom.isEmpty) {
      _notify('请填写自定义类型名称');
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

    final entered = parseYuanToCents(_balance.text);
    var principal = entered;
    var adjustment = 0;

    if (_isInvestment) {
      final existing = widget.existing;
      if (existing != null) {
        final base = _principal ?? existing.balanceInit;
        principal = base + (entered - existing.balanceInit);
      }
      final marketText = _marketValue.text.trim();
      final market = marketText.isEmpty ? principal : parseYuanToCents(marketText);
      adjustment = market - principal;
    }

    setState(() => _saving = true);
    try {
      final id = await ref.read(financeRepositoryProvider).saveAccount(
            id: widget.existing?.id,
            name: name,
            type: _type,
            balanceInit: _isLiability ? entered.abs() : entered,
            customType: _type.isCustom ? custom : null,
            marketAdjustment: _isInvestment ? adjustment : 0,
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

  void _selectClass(AccountClass cls) {
    if (cls == _accountClass) return;
    setState(() {
      _accountClass = cls;
      _type = accountTypesOf(cls).first;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final types = accountTypesOf(_accountClass);
    final principal = _isInvestment
        ? (_principal ?? parseYuanToCents(_balance.text))
        : 0;
    final market = _isInvestment && _marketValue.text.trim().isNotEmpty
        ? parseYuanToCents(_marketValue.text)
        : principal;
    final profit = market - principal;

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
          Text('账户大类', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<AccountClass>(
            segments: [
              for (final cls in AccountClass.values)
                ButtonSegment(value: cls, label: Text(cls.label)),
            ],
            selected: {_accountClass},
            showSelectedIcon: false,
            onSelectionChanged: (values) => _selectClass(values.first),
          ),
          const SizedBox(height: 18),
          Text('账户类型', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in types)
                ChoiceChip(
                  label: Text(option.label),
                  selected: _type == option,
                  onSelected: (_) => setState(() => _type = option),
                ),
            ],
          ),
          if (_type.isCustom) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _customType,
              decoration: InputDecoration(
                labelText: '自定义类型名称',
                hintText: switch (_accountClass) {
                  AccountClass.asset => '例如：公积金、押金',
                  AccountClass.investment => '例如：黄金、数字资产',
                  AccountClass.liability => '例如：装修欠款',
                },
              ),
            ),
          ],
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
            decoration: InputDecoration(
              labelText: switch (_accountClass) {
                AccountClass.asset => '初始余额',
                AccountClass.investment => _editing ? '初始本金' : '初始投入本金',
                AccountClass.liability => '当前欠款',
              },
              prefixText: '¥ ',
              hintText: _isLiability ? '填正数，例如 1702.47' : '0.00',
            ),
          ),
          if (_isInvestment) ...[
            const SizedBox(height: 20),
            TextField(
              controller: _marketValue,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              decoration: const InputDecoration(
                labelText: '当前市值',
                prefixText: '¥ ',
                hintText: '留空则等于本金',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '累计本金 ${formatCents(principal)} · '
              '盈亏 ${profit >= 0 ? '+' : ''}${formatCents(profit)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: profit < 0
                    ? theme.colorScheme.error
                    : theme.colorScheme.outline,
              ),
            ),
          ],
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
