/// 词库批量导入的解析器：支持 CSV/TXT 与 JSON 两种格式，纯函数便于单元测试。
///
/// 支持的文本格式（一行为一个词，`,` 或 `Tab` 分隔，也可用空格）：
/// ```
/// spelling, phonetic, meanings, examples
/// apple, /ˈæpl/, n. 苹果;v. 苹果树, An apple a day keeps the doctor away.
/// ```
/// - 音标列可选，识别为 `/.../` 或 `[...]` 形式
/// - 多个释义用 `;` `；` `|` 分隔
/// - 多个例句用 `|` 分隔
/// - 以 `#` 开头的行与空行会被跳过，首行若像表头也会跳过
///
/// 支持的 JSON 格式：数组，或 `{"words": [...]}`，每项字段为
/// `spelling`（或 `word`）、`phonetic`（或 `phonetic_uk`）、`phonetic_us`、
/// `meanings`（或 `meaning`）、`examples`（或 `example`）。
library;

import 'dart:convert';

class ImportedWord {
  const ImportedWord({
    required this.spelling,
    this.phoneticUk,
    this.phoneticUs,
    this.meanings = const [],
    this.examples = const [],
  });

  final String spelling;
  final String? phoneticUk;
  final String? phoneticUs;
  final List<String> meanings;
  final List<String> examples;
}

class WordImportResult {
  const WordImportResult({
    required this.words,
    required this.issues,
    required this.totalItems,
  });

  final List<ImportedWord> words;

  /// 跳过的条目及原因，用于在预览里展示。
  final List<String> issues;

  /// 解析前的条目总数（文本为数据行数，JSON 为数组长度）。
  final int totalItems;

  int get skipped => totalItems - words.length;

  bool get isEmpty => words.isEmpty;
}

final _phoneticPattern = RegExp(r'^[/\[].*[/\]]$');
final _wordPattern = RegExp(r'[A-Za-z]');
final _listSeparator = RegExp(r'[;；|]');
final _headerKeywords = ['spelling', 'word', 'phonetic', 'meaning', '拼写', '单词', '释义'];

/// 解析导入内容；自动识别 JSON 与分隔文本。
WordImportResult parseWordImport(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) {
    return const WordImportResult(
      words: [],
      issues: ['内容为空'],
      totalItems: 0,
    );
  }

  final looksLikeJson = trimmed.startsWith('[') || trimmed.startsWith('{');
  return looksLikeJson ? _parseJson(trimmed) : _parseDelimited(content);
}

WordImportResult _parseJson(String content) {
  final Object? decoded;
  try {
    decoded = jsonDecode(content);
  } on FormatException catch (error) {
    return WordImportResult(
      words: const [],
      issues: ['JSON 解析失败：${error.message}'],
      totalItems: 0,
    );
  }

  final List<dynamic> items;
  switch (decoded) {
    case List<dynamic> list:
      items = list;
    case Map<String, dynamic> map when map['words'] is List:
      items = map['words'] as List<dynamic>;
    default:
      return const WordImportResult(
        words: [],
        issues: ['JSON 结构不支持，期望数组或 {"words": [...]}'],
        totalItems: 0,
      );
  }

  final issues = <String>[];
  final words = <ImportedWord>[];
  final seen = <String>{};

  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    if (item is! Map<String, dynamic>) {
      issues.add('第 ${index + 1} 项不是对象');
      continue;
    }

    final spelling = _clean(item['spelling'] ?? item['word']);
    if (spelling == null) {
      issues.add('第 ${index + 1} 项缺少拼写');
      continue;
    }
    if (!seen.add(spelling.toLowerCase())) {
      issues.add('第 ${index + 1} 项「$spelling」与前面重复');
      continue;
    }

    words.add(
      ImportedWord(
        spelling: spelling,
        phoneticUk: _clean(
          item['phonetic'] ?? item['phonetic_uk'] ?? item['phoneticUk'],
        ),
        phoneticUs: _clean(item['phonetic_us'] ?? item['phoneticUs']),
        meanings: _splitList(item['meanings'] ?? item['meaning']),
        examples: _splitList(item['examples'] ?? item['example']),
      ),
    );
  }

  return WordImportResult(
    words: words,
    issues: issues,
    totalItems: items.length,
  );
}

WordImportResult _parseDelimited(String content) {
  final issues = <String>[];
  final words = <ImportedWord>[];
  final seen = <String>{};
  final lines = content.split('\n');
  var dataItems = 0;
  var headerChecked = false;

  for (var index = 0; index < lines.length; index++) {
    final raw = lines[index].trim();
    if (raw.isEmpty || raw.startsWith('#')) continue;

    // 首行若含表头关键词则整行跳过
    if (!headerChecked) {
      headerChecked = true;
      final lower = raw.toLowerCase();
      if (_headerKeywords.any(lower.contains)) continue;
    }

    dataItems++;
    final cells = _splitCells(raw);
    final spelling = cells.isEmpty ? '' : cells.first;

    if (spelling.isEmpty) {
      issues.add('第 ${index + 1} 行没有单词');
      continue;
    }
    if (!_wordPattern.hasMatch(spelling)) {
      issues.add('第 ${index + 1} 行「$spelling」不像英文单词');
      continue;
    }
    if (!seen.add(spelling.toLowerCase())) {
      issues.add('第 ${index + 1} 行「$spelling」与前面重复');
      continue;
    }

    String? phonetic;
    var meaningIndex = 1;
    if (cells.length > 1 && _phoneticPattern.hasMatch(cells[1])) {
      phonetic = cells[1];
      meaningIndex = 2;
    }

    words.add(
      ImportedWord(
        spelling: spelling,
        phoneticUk: phonetic,
        meanings: cells.length > meaningIndex
            ? _splitList(cells[meaningIndex])
            : const [],
        examples: cells.length > meaningIndex + 1
            ? _splitList(cells[meaningIndex + 1])
            : const [],
      ),
    );
  }

  return WordImportResult(
    words: words,
    issues: issues,
    totalItems: dataItems,
  );
}

List<String> _splitCells(String line) {
  final List<String> cells;
  if (line.contains(',')) {
    cells = line.split(',');
  } else if (line.contains('\t')) {
    cells = line.split('\t');
  } else {
    // 空格分隔：第一个空格前是单词，其余是释义
    final index = line.indexOf(RegExp(r'[ \u3000]'));
    cells = index < 0
        ? [line]
        : [line.substring(0, index), line.substring(index + 1)];
  }
  return [for (final cell in cells) cell.trim()];
}

List<String> _splitList(Object? value) {
  Iterable<String> parts;
  if (value is List) {
    parts = [for (final item in value) if (item != null) '$item'];
  } else if (value is String) {
    parts = value.split(_listSeparator);
  } else {
    return const [];
  }
  return [
    for (final part in parts)
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

String? _clean(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return null;
  return trimmed;
}
