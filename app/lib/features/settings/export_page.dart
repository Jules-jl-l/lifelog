/// 数据导出：把流水、健康、学习数据导出为 CSV 并分享。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/export/csv_export.dart';
import '../../data/providers.dart';

class ExportPage extends ConsumerStatefulWidget {
  const ExportPage({super.key});

  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  final _selected = <ExportKind>{...ExportKind.values};
  bool _busy = false;
  String? _status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('导出 CSV')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '选择要导出的数据，生成 UTF-8 CSV 文件（带 BOM，Excel 可直接打开），'
                '通过系统分享保存到电脑、网盘或聊天工具。\n'
                '导出的内容不包含回收站中已删除的记录。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final kind in ExportKind.values)
            CheckboxListTile(
              value: _selected.contains(kind),
              title: Text(kind.label),
              subtitle: Text(_subtitleFor(kind)),
              onChanged: _busy
                  ? null
                  : (checked) {
                      setState(() {
                        if (checked == true) {
                          _selected.add(kind);
                        } else {
                          _selected.remove(kind);
                        }
                      });
                    },
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed:
                _busy || _selected.isEmpty ? null : _export,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('生成并分享 CSV'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_status!, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }

  String _subtitleFor(ExportKind kind) => switch (kind) {
        ExportKind.transactions => '日期、类型、金额、分类、账户、商户、备注',
        ExportKind.weight => '日期、体重、体脂率、备注',
        ExportKind.measure => '日期、部位、数值、备注',
        ExportKind.workout => '日期、类型、时长、距离、消耗、心率',
        ExportKind.study => '每日新词、复习、正确率、用时',
        ExportKind.quiz => '每次测验的词库、模式、题数、正确率',
      };

  Rect _shareOrigin(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    return const Rect.fromLTWH(0, 0, 1, 1);
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _status = null;
    });

    try {
      final service = ref.read(exportServiceProvider);
      final contents = await service.build(_selected);
      final files = await service.writeToFiles(contents);
      if (!mounted) return;
      setState(() {
        _status = '已生成 ${files.length} 个 CSV 文件';
        _busy = false;
      });

      await SharePlus.instance.share(
        ShareParams(
          files: [for (final file in files) XFile(file.path)],
          subject: '朝夕册 CSV 导出',
          text: '朝夕册导出的 CSV 数据（UTF-8）。',
          // iPad 上分享面板以 popover 呈现，必须给出锚点
          sharePositionOrigin: _shareOrigin(context),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = '导出失败：$error';
        _busy = false;
      });
    }
  }
}
