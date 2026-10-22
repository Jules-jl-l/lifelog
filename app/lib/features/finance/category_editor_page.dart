/// 新建 / 编辑分类页面。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/providers.dart';

class CategoryEditorPage extends ConsumerStatefulWidget {
  const CategoryEditorPage({
    super.key,
    this.existing,
    this.initialKind = TxnKind.expense,
  });

  final Category? existing;
  final TxnKind initialKind;

  @override
  ConsumerState<CategoryEditorPage> createState() => _CategoryEditorPageState();
}

class _CategoryEditorPageState extends ConsumerState<CategoryEditorPage> {
  late final TextEditingController _name;
  late TxnKind _kind;
  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _kind = widget.existing?.kind ?? widget.initialKind;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写分类名称')));
      return;
    }

    setState(() => _saving = true);
    try {
      final id = await ref.read(financeRepositoryProvider).saveCategory(
            id: widget.existing?.id,
            name: name,
            kind: _kind,
            sort: widget.existing?.sort ?? 0,
          );
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? '编辑分类' : '新建分类')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          TextField(
            controller: _name,
            autofocus: !_editing,
            decoration: const InputDecoration(
              labelText: '分类名称',
              hintText: '例如：餐饮、交通、工资',
            ),
          ),
          const SizedBox(height: 20),
          Text('收支方向', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<TxnKind>(
            segments: const [
              ButtonSegment(value: TxnKind.expense, label: Text('支出')),
              ButtonSegment(value: TxnKind.income, label: Text('收入')),
            ],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (values) =>
                setState(() => _kind = values.first),
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
