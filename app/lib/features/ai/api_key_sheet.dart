/// DeepSeek API Key 配置弹窗。
///
/// Key 只写入本机安全存储（Android Keystore），界面只显示掩码，不回显完整值。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'ai_providers.dart';

/// 掩码展示：只暴露前 5 位与后 4 位。
String maskApiKey(String key) => key.length <= 10
    ? '****'
    : '${key.substring(0, 5)}…${key.substring(key.length - 4)}';

Future<void> openApiKeyDialog(
  BuildContext context, {
  required String? currentKey,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ApiKeyDialog(currentKey: currentKey),
  );
}

/// 对话框自己持有输入控制器。
///
/// 如果像早期实现那样在 `showDialog` 返回后立刻 dispose，
/// 退场动画期间 TextField 仍会重建，会报「used after being disposed」。
class _ApiKeyDialog extends ConsumerStatefulWidget {
  const _ApiKeyDialog({required this.currentKey});

  final String? currentKey;

  @override
  ConsumerState<_ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends ConsumerState<_ApiKeyDialog> {
  final _controller = TextEditingController();

  bool get _hasKey =>
      widget.currentKey != null && widget.currentKey!.isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    await ref.read(securityStoreProvider).saveApiKey(value);
    ref.invalidate(apiKeyConfiguredProvider);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _clear() async {
    await ref.read(securityStoreProvider).clearApiKey();
    ref.invalidate(apiKeyConfiguredProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('DeepSeek API Key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _hasKey
                ? '已配置：${maskApiKey(widget.currentKey!)}。填入新值会覆盖旧值。'
                : '还没有配置。Key 只保存在本机安全存储，不会上传、也不会写进代码仓库。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: !_hasKey,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-...',
            ),
          ),
        ],
      ),
      actions: [
        if (_hasKey)
          TextButton(
            onPressed: _clear,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('清除'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
