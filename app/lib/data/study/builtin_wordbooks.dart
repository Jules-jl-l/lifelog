/// 内置词库：从 assets/wordlists 加载 CET-4 / CET-6 / 考研英语 / IT 行业词汇。
library;

import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// 当前默认内置词库（AI 工具默认加词也用它）。
const defaultBuiltinWordbookName = 'CET-4';

/// 旧版本内置词库名：升级时复用该词库并补充为完整 CET-4，避免出现两本重复词库。
const legacyBuiltinWordbookName = 'CET-4 核心词';

class BuiltinWordData {
  const BuiltinWordData({required this.spelling, required this.meanings});

  final String spelling;
  final List<String> meanings;
}

class BuiltinWordbookData {
  const BuiltinWordbookData({
    required this.slug,
    required this.name,
    required this.source,
    required this.words,
  });

  final String slug;
  final String name;
  final String source;
  final List<BuiltinWordData> words;
}

const _assets = <({String slug, String name})>[
  (slug: 'cet4', name: 'CET-4'),
  (slug: 'cet6', name: 'CET-6'),
  (slug: 'kaoyan', name: '考研英语'),
  (slug: 'it', name: 'IT 行业必备词汇'),
];

/// 加载全部内置词库。资源缺失时抛出异常，由调用方兜底。
Future<List<BuiltinWordbookData>> loadBuiltinWordbooks({
  AssetBundle? bundle,
}) async {
  final assets = bundle ?? rootBundle;
  final result = <BuiltinWordbookData>[];
  for (final spec in _assets) {
    final raw = await assets.loadString('assets/wordlists/${spec.slug}.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final rows = map['words'] as List<dynamic>? ?? const [];
    result.add(
      BuiltinWordbookData(
        slug: spec.slug,
        name: (map['name'] as String?) ?? spec.name,
        source: (map['source'] as String?) ?? 'builtin',
        words: [
          for (final row in rows)
            if (row is List && row.length >= 2)
              BuiltinWordData(
                spelling: row[0] as String,
                meanings: [row[1] as String],
              ),
        ],
      ),
    );
  }
  return result;
}
