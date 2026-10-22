/// 备份与恢复页：导出加密备份包 / 从备份包恢复。
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/async_x.dart';
import '../../core/utils.dart';
import '../../data/backup/backup_codec.dart';
import '../../data/providers.dart';
import '../../data/settings_repository.dart';

/// 超过该天数未备份就在设置页提示。
const backupReminderDays = 7;

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;
  String? _status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastBackup = ref.watch(lastBackupAtProvider).dataOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        lastBackup == null
                            ? Icons.warning_amber_rounded
                            : Icons.verified_outlined,
                        color: lastBackup == null ||
                                _daysSince(lastBackup) >= backupReminderDays
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          lastBackup == null
                              ? '还没有备份过'
                              : '上次备份：${formatDateTime(lastBackup.toLocal())}'
                                  '（${_daysSince(lastBackup)} 天前）',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '数据只保存在本机，换机、丢机或误删且没有备份时无法找回。'
                    '建议每 $backupReminderDays 天导出一次。',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.lock_outline),
            label: const Text('导出加密备份包'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.restore),
            label: const Text('从备份包恢复'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_status!, style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '备份包用你的备份密码经 PBKDF2 派生密钥、AES-256-GCM 加密，'
                '文件本身不含明文数据。\n'
                '• 备份密码请单独记牢：密码丢失则备份无法恢复\n'
                '• PIN 码与 API Key 存在系统安全存储，不在备份包内，'
                '恢复后仍沿用当前设备的设置',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _daysSince(DateTime value) =>
      DateTime.now().difference(value.toLocal()).inDays;

  Future<void> _export() async {
    final password = await _askPassword(confirm: true);
    if (password == null || !mounted) return;

    setState(() {
      _busy = true;
      _status = null;
    });

    try {
      final service = ref.read(backupServiceProvider);
      final bytes = await service.exportEncrypted(password);
      final file = await service.writeToFile(bytes);
      await ref
          .read(settingsRepositoryProvider)
          .set(SettingKeys.lastBackupAt, DateTime.now().toIso8601String());

      if (!mounted) return;
      setState(() => _status = '已生成 ${file.path.split('/').last}（${bytes.length} 字节）');

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: '朝夕册 加密备份包',
          text: '请连同备份密码一起妥善保存；数据只在本机，这份备份是唯一的兜底。',
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _status = '导出失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null || !mounted) return;

    final Uint8List bytes;
    try {
      bytes = await picked.xFile.readAsBytes();
    } catch (error) {
      if (mounted) setState(() => _status = '无法读取所选文件：$error');
      return;
    }
    if (!mounted) return;

    final password = await _askPassword(confirm: false);
    if (password == null || !mounted) return;

    setState(() {
      _busy = true;
      _status = null;
    });

    try {
      final payload = await decodeBackup(bytes: bytes, password: password);
      if (!mounted) return;

      final replace = await _confirmRestore(payload);
      if (replace == null || !mounted) {
        setState(() => _busy = false);
        return;
      }

      final report =
          await ref.read(backupServiceProvider).restore(payload, replace: replace);
      if (!mounted) return;
      setState(() {
        _status = '已恢复 ${report.tables} 张表、${report.rows} 行数据';
        _busy = false;
      });
    } on BackupException catch (error) {
      if (mounted) {
        setState(() {
          _status = error.message;
          _busy = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = '恢复失败：$error';
          _busy = false;
        });
      }
    }
  }

  /// 输入备份密码；[confirm] 为 true 时要求二次确认（导出用）。
  Future<String?> _askPassword({required bool confirm}) async {
    final first = TextEditingController();
    final second = TextEditingController();
    String? error;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(confirm ? '设置备份密码' : '输入备份密码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                confirm
                    ? '这个密码用于加密备份包，请单独记牢；丢失后备份无法恢复。'
                    : '输入导出时设置的备份密码。',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: first,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '备份密码',
                  hintText: '至少 8 位',
                ),
              ),
              if (confirm) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: second,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '再次输入'),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final value = first.text;
                if (value.length < 8) {
                  setDialogState(() => error = '密码至少 8 位');
                  return;
                }
                if (confirm && value != second.text) {
                  setDialogState(() => error = '两次输入不一致');
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );

    first.dispose();
    second.dispose();
    return result;
  }

  /// 展示备份概要并选择恢复方式；返回 null 表示取消。
  Future<bool?> _confirmRestore(BackupPayload payload) async {
    final theme = Theme.of(context);
    final info = payload.info;

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认恢复'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('导出于 ${formatDateTime(info.exportedAt.toLocal())}'),
            const SizedBox(height: 8),
            Text('包含 ${info.tableCounts.length} 张表、共 ${info.totalRows} 行'),
            const SizedBox(height: 16),
            Text(
              '「覆盖恢复」会清空当前全部数据后写入备份内容；'
              '「合并导入」按主键覆盖同名记录、保留其余数据。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('合并导入'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            child: const Text('覆盖恢复'),
          ),
        ],
      ),
    );
  }
}
