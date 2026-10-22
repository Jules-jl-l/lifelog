/// 回收站：查看、恢复或彻底删除软删除的数据。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/providers.dart';
import '../../data/recycle_bin_repository.dart';

class RecycleBinPage extends ConsumerStatefulWidget {
  const RecycleBinPage({super.key});

  @override
  ConsumerState<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends ConsumerState<RecycleBinPage> {
  List<RecycleItem>? _items;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await ref.read(recycleBinRepositoryProvider).list();
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          if (items != null && items.isNotEmpty)
            IconButton(
              tooltip: '清空回收站',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _busy ? null : () => _clearAll(items.length),
            ),
        ],
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 48,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '回收站是空的',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '删除的流水、健康记录、单词等会先放在这里',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      leading: Icon(_iconFor(item.kind)),
                      title: Text(item.title),
                      subtitle: Text(
                        '${item.kind.label}'
                        '${item.subtitle.isEmpty ? '' : ' · ${item.subtitle}'}'
                        '\n删除于 ${formatDateTime(item.deletedAt)}',
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        enabled: !_busy,
                        onSelected: (value) {
                          if (value == 'restore') {
                            _restore(item);
                          } else {
                            _deleteForever(item);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'restore',
                            child: Text('恢复'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('彻底删除'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  IconData _iconFor(RecycleKind kind) => switch (kind) {
        RecycleKind.transaction => Icons.receipt_long_outlined,
        RecycleKind.account => Icons.account_balance_wallet_outlined,
        RecycleKind.category => Icons.category_outlined,
        RecycleKind.budget => Icons.savings_outlined,
        RecycleKind.weight => Icons.monitor_weight_outlined,
        RecycleKind.measure => Icons.straighten,
        RecycleKind.workout => Icons.directions_run,
        RecycleKind.word => Icons.abc,
        RecycleKind.wordbook => Icons.menu_book_outlined,
      };

  Future<void> _restore(RecycleItem item) async {
    setState(() => _busy = true);
    try {
      await ref.read(recycleBinRepositoryProvider).restore(item);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已恢复：${item.title}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteForever(RecycleItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('彻底删除？'),
        content: Text('「${item.title}」删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(recycleBinRepositoryProvider).deleteForever(item);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已彻底删除')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAll(int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空回收站？'),
        content: Text('将彻底删除 $count 条记录，且无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final removed = await ref.read(recycleBinRepositoryProvider).clearAll();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已清空 $removed 条记录')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
