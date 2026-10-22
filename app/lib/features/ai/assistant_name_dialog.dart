/// 修改 AI 助手名字的弹窗：AI 页和「我的」共用。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/settings_repository.dart';
import 'ai_providers.dart';

/// 名字允许的最大长度。
const assistantNameMaxLength = 12;

/// 打开改名弹窗；保存后写入设置并刷新 [assistantNameProvider]。
Future<void> openAssistantNameDialog(
  BuildContext context,
  WidgetRef ref, {
  required String current,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AssistantNameDialog(current: current, ref: ref),
  );
}

class _AssistantNameDialog extends StatefulWidget {
  const _AssistantNameDialog({required this.current, required this.ref});

  final String current;
  final WidgetRef ref;

  @override
  State<_AssistantNameDialog> createState() => _AssistantNameDialogState();
}

class _AssistantNameDialogState extends State<_AssistantNameDialog> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名字不能为空')),
      );
      return;
    }

    setState(() => _saving = true);
    await widget.ref.read(settingsRepositoryProvider).set(
          SettingKeys.assistantName,
          name,
        );
    widget.ref.invalidate(assistantNameProvider);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('以后就叫「$name」啦')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('给助手起个名字'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: assistantNameMaxLength,
        inputFormatters: [
          LengthLimitingTextInputFormatter(assistantNameMaxLength),
        ],
        decoration: InputDecoration(
          labelText: '助手名字',
          hintText: '默认「$defaultAssistantName」',
          counterText: '',
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
