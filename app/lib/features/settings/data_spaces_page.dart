/// 数据空间管理：新建（空白 / 复制当前）、切换、重命名、删除。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/providers.dart';

enum _SpaceAction { rename, delete }

class DataSpacesPage extends ConsumerStatefulWidget {
  const DataSpacesPage({super.key});

  @override
  ConsumerState<DataSpacesPage> createState() => _DataSpacesPageState();
}

class _DataSpacesPageState extends ConsumerState<DataSpacesPage> {
  Map<String, int> _sizes = const {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSizes();
  }

  Future<void> _loadSizes() async {
    final store = ref.read(spaceStoreProvider);
    final spaces = ref.read(spaceControllerProvider).spaces;
    final sizes = <String, int>{};
    for (final space in spaces) {
      sizes[space.id] = await store.fileSize(space);
    }
    if (mounted) setState(() => _sizes = sizes);
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error) {
      if (mounted) _toast('$failure：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(spaceControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据空间'),
        actions: [
          IconButton(
            tooltip: '新建数据空间',
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                '每个空间是一份独立的数据，互不影响。切换后财务、健康、学习与 AI '
                '都会读取对应空间，适合把测试数据与真实数据分开保存。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final space in state.spaces)
                Card(
                  clipBehavior: Clip.antiAlias,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      space.id == state.currentId
                          ? Icons.folder_special_outlined
                          : Icons.folder_outlined,
                      color: space.id == state.currentId
                          ? theme.colorScheme.primary
                          : null,
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            space.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (space.id == state.currentId) ...[
                          const SizedBox(width: 8),
                          _CurrentBadge(),
                        ],
                      ],
                    ),
                    subtitle: Text(_subtitle(space)),
                    onTap: space.id == state.currentId || _busy
                        ? null
                        : () => _switchTo(space),
                    trailing: PopupMenuButton<_SpaceAction>(
                      enabled: !_busy,
                      tooltip: '更多操作',
                      onSelected: (action) => switch (action) {
                        _SpaceAction.rename => _rename(space),
                        _SpaceAction.delete => _delete(space),
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: _SpaceAction.rename,
                          child: Text('重命名'),
                        ),
                        PopupMenuItem(
                          value: _SpaceAction.delete,
                          enabled: space.id != state.currentId,
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.add),
                label: const Text('新建数据空间'),
              ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  String _subtitle(DataSpace space) {
    final parts = <String>[
      _formatSize(_sizes[space.id]),
      if (space.createdAt == null)
        '初始空间'
      else
        '创建于 ${formatDate(space.createdAt!)}',
    ];
    return parts.join(' · ');
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '统计中';
    if (bytes <= 0) return '暂无数据';
    const kb = 1024;
    if (bytes < kb * kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '${(bytes / kb / kb).toStringAsFixed(1)} MB';
  }

  Future<void> _switchTo(DataSpace space) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('切换到「${space.name}」？'),
        content: const Text('财务、健康、学习与 AI 都会改为显示该空间的数据，可以随时切回。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('切换'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(
      () => ref.read(spaceControllerProvider.notifier).switchTo(space.id),
      '切换失败',
    );
  }

  Future<void> _create() async {
    final result = await showDialog<_CreateSpaceResult>(
      context: context,
      builder: (_) => const _CreateSpaceDialog(),
    );
    if (result == null) return;

    // 先取当前库，创建过程中会切到新空间
    final source = result.copyCurrent ? ref.read(databaseProvider) : null;
    await _run(() async {
      await ref.read(spaceControllerProvider.notifier).create(
            name: result.name,
            copyFrom: source,
          );
      await _loadSizes();
    }, '新建失败');
  }

  Future<void> _rename(DataSpace space) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameSpaceDialog(initialName: space.name),
    );
    if (name == null) return;

    await _run(
      () => ref.read(spaceControllerProvider.notifier).rename(space.id, name),
      '重命名失败',
    );
  }

  Future<void> _delete(DataSpace space) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除「${space.name}」？'),
        content: const Text('该空间的全部记录会被永久删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() async {
      await ref.read(spaceControllerProvider.notifier).delete(space.id);
      await _loadSizes();
    }, '删除失败');
  }
}

class _CreateSpaceResult {
  const _CreateSpaceResult({required this.name, required this.copyCurrent});

  final String name;
  final bool copyCurrent;
}

/// 对话框自己持有输入控制器，路由退场动画结束后再释放。
class _CreateSpaceDialog extends StatefulWidget {
  const _CreateSpaceDialog();

  @override
  State<_CreateSpaceDialog> createState() => _CreateSpaceDialogState();
}

class _CreateSpaceDialogState extends State<_CreateSpaceDialog> {
  final _controller = TextEditingController(text: '测试数据');
  bool _copyCurrent = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建数据空间'),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 24,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例如：测试数据',
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '复制当前数据',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Switch(
                    value: _copyCurrent,
                    onChanged: (value) =>
                        setState(() => _copyCurrent = value),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '以当前数据为副本，原空间不受影响',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _CreateSpaceResult(
              name: _controller.text,
              copyCurrent: _copyCurrent,
            ),
          ),
          child: const Text('创建'),
        ),
      ],
    );
  }
}

class _RenameSpaceDialog extends StatefulWidget {
  const _RenameSpaceDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameSpaceDialog> createState() => _RenameSpaceDialogState();
}

class _RenameSpaceDialogState extends State<_RenameSpaceDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名数据空间'),
      content: SizedBox(
        width: 300,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(labelText: '名称'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _CurrentBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '当前',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
