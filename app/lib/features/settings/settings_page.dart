/// 我的：本地锁、备份、AI 配置入口。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_x.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/providers.dart';
import '../../data/settings_repository.dart';
import '../ai/ai_providers.dart';
import '../ai/api_key_sheet.dart';
import '../ai/assistant_name_dialog.dart';
import '../lock/lock_state.dart';
import 'backup_page.dart';
import 'export_page.dart';
import 'recycle_bin_page.dart';
import 'theme_color_sheet.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
          const _SectionTitle('安全'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('立即锁定'),
            onTap: () => ref.read(lockStatusProvider.notifier).lock(),
          ),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('修改 PIN'),
            onTap: () => _changePin(context, ref),
          ),
          Consumer(
            builder: (context, ref, _) {
              final skip =
                  ref.watch(skipPinOnStartProvider).dataOrNull ?? false;
              return SwitchListTile(
                secondary: const Icon(Icons.lock_open_outlined),
                title: const Text('启动免 PIN'),
                subtitle: Text(
                  skip
                      ? '已开启：启动直接进入主界面，仅手动「立即锁定」后需要 PIN'
                      : '关闭：每次启动需要输入 PIN',
                ),
                value: skip,
                onChanged: (value) async {
                  await ref.read(settingsRepositoryProvider).set(
                        SettingKeys.skipPinOnStart,
                        value ? '1' : '0',
                      );
                  ref.invalidate(skipPinOnStartProvider);
                },
              );
            },
          ),
          const Divider(),
          const _SectionTitle('外观'),
          Consumer(
            builder: (context, ref, _) {
              final accent =
                  ref.watch(themeAccentProvider).dataOrNull ?? ThemeAccent.green;
              return ListTile(
                leading: Icon(Icons.palette_outlined, color: accent.seed),
                title: const Text('主题颜色'),
                subtitle: Text('当前「${accent.label}」· 点击换一个颜色'),
                trailing: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: accent.seed,
                    shape: BoxShape.circle,
                  ),
                ),
                onTap: () =>
                    openThemeColorSheet(context, ref, current: accent),
              );
            },
          ),
          const Divider(),
          const _SectionTitle('数据'),
          Consumer(
            builder: (context, ref, _) {
              final lastBackup = ref.watch(lastBackupAtProvider).dataOrNull;
              final stale = lastBackup == null ||
                  DateTime.now().difference(lastBackup.toLocal()).inDays >=
                      backupReminderDays;
              return ListTile(
                leading: Icon(
                  Icons.backup_outlined,
                  color: stale ? Theme.of(context).colorScheme.error : null,
                ),
                title: const Text('备份与恢复'),
                subtitle: Text(
                  lastBackup == null
                      ? '还没有备份过 · 数据只在本机一份'
                      : '上次备份 ${formatDateTime(lastBackup.toLocal())}',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const BackupPage()),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('导出 CSV'),
            subtitle: const Text('流水 / 健康 / 学习数据，可直接用 Excel 打开'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ExportPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('回收站'),
            subtitle: const Text('恢复误删的流水、记录与单词'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RecycleBinPage()),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.storage_outlined),
            title: Text('数据存储'),
            subtitle: Text('全部数据保存在本机 SQLite，不上传任何服务器'),
            enabled: false,
          ),
          const Divider(),
          const _SectionTitle('AI 助手'),
          Consumer(
            builder: (context, ref, _) {
              final name = ref.watch(assistantNameProvider).dataOrNull ??
                  defaultAssistantName;
              return ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('助手名称'),
                subtitle: Text('当前叫「$name」· 点击可以给 TA 改个名字'),
                onTap: () => openAssistantNameDialog(
                  context,
                  ref,
                  current: name,
                ),
              );
            },
          ),
          Consumer(
            builder: (context, ref, _) {
              final configured =
                  ref.watch(apiKeyConfiguredProvider).dataOrNull ?? false;
              return ListTile(
                leading: const Icon(Icons.psychology_outlined),
                title: const Text('DeepSeek API Key'),
                subtitle: Text(
                  configured ? '已配置 · 点击可修改或清除' : '未配置 · 配置后可使用 AI 对话与识图记账',
                ),
                onTap: () async {
                  final key =
                      await ref.read(securityStoreProvider).readApiKey();
                  if (!context.mounted) return;
                  await openApiKeyDialog(context, currentKey: key);
                },
              );
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '朝夕册 v0.3.0 · 数据只有本机一份，请定期导出备份。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changePin(BuildContext context, WidgetRef ref) async {
    final store = ref.read(securityStoreProvider);

    final current = TextEditingController();
    final verified = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('输入当前 PIN'),
        content: _PinField(controller: current),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final ok = await store.verifyPin(current.text);
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop(ok);
              }
            },
            child: const Text('下一步'),
          ),
        ],
      ),
    );

    if (verified != true || !context.mounted) {
      if (verified == false && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('当前 PIN 不正确')));
      }
      return;
    }

    await store.clearPin();
    if (!context.mounted) return;
    ref.read(lockStatusProvider.notifier).lock();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清除 PIN，请在锁屏页重新设置')),
    );
  }
}

class _PinField extends StatelessWidget {
  const _PinField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(8),
      ],
      decoration: const InputDecoration(labelText: 'PIN 码'),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}
