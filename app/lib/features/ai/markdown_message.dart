/// AI 回复的 Markdown 渲染。
///
/// 目标是「看起来像聊天，而不是一堆符号」：标题、列表、代码块、表格都按
/// 主题配色排版，紧凑间距，不额外撑高气泡。
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class MarkdownMessage extends StatelessWidget {
  const MarkdownMessage({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final base = MarkdownStyleSheet.fromTheme(theme);

    return MarkdownBody(
      data: data,
      selectable: false,
      styleSheet: base.copyWith(
        p: body.copyWith(height: 1.5),
        h1: (theme.textTheme.titleLarge ?? body)
            .copyWith(fontWeight: FontWeight.w700, height: 1.35),
        h2: (theme.textTheme.titleMedium ?? body)
            .copyWith(fontWeight: FontWeight.w700, height: 1.35),
        h3: body.copyWith(fontWeight: FontWeight.w700, fontSize: 15, height: 1.35),
        strong: body.copyWith(fontWeight: FontWeight.w700),
        em: body.copyWith(fontStyle: FontStyle.italic),
        listBullet: body.copyWith(height: 1.45),
        listIndent: 18,
        blockSpacing: 6,
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.4,
          color: scheme.onSurface,
          backgroundColor: scheme.surfaceContainerHigh,
        ),
        codeblockPadding: const EdgeInsets.all(10),
        codeblockDecoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        blockquotePadding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: scheme.outlineVariant, width: 3),
          ),
        ),
        tableBorder: TableBorder.all(
          color: scheme.outlineVariant,
          width: 0.6,
        ),
        tableCellsPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
      ),
    );
  }
}
