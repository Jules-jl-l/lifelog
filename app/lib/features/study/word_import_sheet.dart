/// 词库批量导入弹层：选目标词库 → 粘贴或选文件 → 预览 → 导入。
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_x.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import '../../data/study/word_import.dart';
import 'study_providers.dart';

Future<void> openWordImport(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const WordImportSheet(),
  );
}

class WordImportSheet extends ConsumerStatefulWidget {
  const WordImportSheet({super.key});

  @override
  ConsumerState<WordImportSheet> createState() => _WordImportSheetState();
}

class _WordImportSheetState extends ConsumerState<WordImportSheet> {
  final _newBookName = TextEditingController();
  final _content = TextEditingController();

  String? _bookId;
  bool _creatingNew = false;
  String? _sourceLabel;
  WordImportResult? _preview;
  bool _importing = false;
  String? _message;

  @override
  void dispose() {
    _newBookName.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final books =
        ref.watch(wordbooksProvider).dataOrNull ?? const <Wordbook>[];
    final selectedBookId =
        _bookId ?? (books.isEmpty ? null : books.first.id);
    // 还没有任何词库时，只能走「新建」这条路
    final creatingNew = _creatingNew || books.isEmpty;
    final preview = _preview;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('批量导入单词', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('目标词库', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final book in books)
                  ChoiceChip(
                    label: Text(book.name),
                    selected: !creatingNew && selectedBookId == book.id,
                    onSelected: (_) => setState(() {
                      _creatingNew = false;
                      _bookId = book.id;
                      _preview = null;
                    }),
                  ),
                ChoiceChip(
                  label: const Text('新建词库'),
                  selected: creatingNew,
                  onSelected: (_) => setState(() {
                    _creatingNew = true;
                    _preview = null;
                  }),
                ),
              ],
            ),
            if (creatingNew) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _newBookName,
                decoration: const InputDecoration(labelText: '新词库名称'),
              ),
            ],
            const SizedBox(height: 20),
            Text('内容来源', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _parsePasted,
                    icon: const Icon(Icons.content_paste_go, size: 18),
                    label: const Text('解析文本'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('选择文件'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _content,
              maxLines: 5,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                labelText: '粘贴内容（CSV / TXT / JSON）',
                hintText: 'apple, /ˈæpl/, n. 苹果',
              ),
            ),
            if (_sourceLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                '已读取：$_sourceLabel',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
            if (preview != null) ..._buildPreview(theme, preview),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _importing || preview == null || preview.isEmpty
                  ? null
                  : _import,
              child: Text(_importing ? '导入中…' : '确认导入'),
            ),
            const SizedBox(height: 8),
            Text(
              '首行若是表头会自动跳过；以 # 开头的行会被忽略；'
              '同一文件内与词库中已存在的拼写会自动去重。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPreview(ThemeData theme, WordImportResult result) {
    final sample = result.words.take(3).map((word) => word.spelling).join('、');

    return [
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '将导入 ${result.words.length} 个词',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                '共 ${result.totalItems} 条，跳过 ${result.skipped} 条',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              if (sample.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('示例：$sample', style: theme.textTheme.bodySmall),
              ],
              if (result.issues.isNotEmpty) ...[
                const SizedBox(height: 4),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text(
                    '跳过明细（${result.issues.length}）',
                    style: theme.textTheme.bodySmall,
                  ),
                  children: [
                    for (final issue in result.issues.take(30))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '· $issue',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  void _parsePasted() {
    final content = _content.text;
    if (content.trim().isEmpty) {
      setState(() => _message = '先粘贴内容，或选择文件');
      return;
    }
    setState(() {
      _preview = parseWordImport(content);
      _sourceLabel = '粘贴内容';
      _message = null;
    });
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null || !mounted) return;

    try {
      final bytes = await picked.xFile.readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      if (!mounted) return;
      _content.text = content;
      setState(() {
        _preview = parseWordImport(content);
        _sourceLabel = picked.name;
        _message = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _message = '读取文件失败：$error');
    }
  }

  Future<void> _import() async {
    final preview = _preview;
    if (preview == null || preview.words.isEmpty) return;

    setState(() {
      _importing = true;
      _message = null;
    });

    try {
      final study = ref.read(studyRepositoryProvider);
      final books =
          ref.read(wordbooksProvider).dataOrNull ?? const <Wordbook>[];

      final String wordbookId;
      if (_creatingNew || books.isEmpty) {
        final name = _newBookName.text.trim();
        if (name.isEmpty) {
          setState(() {
            _importing = false;
            _message = '请填写新词库名称';
          });
          return;
        }
        wordbookId = await study.createWordbook(name: name);
      } else {
        wordbookId = _bookId ?? books.first.id;
      }

      final result = await study.importWords(
        wordbookId: wordbookId,
        words: preview.words,
      );
      if (!mounted) return;

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导入 ${result.added} 个词'
            '${result.duplicated > 0 ? '，跳过 ${result.duplicated} 个重复词' : ''}',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _message = '导入失败：$error';
      });
    }
  }
}
