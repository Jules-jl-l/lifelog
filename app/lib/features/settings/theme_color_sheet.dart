/// 主题颜色选择弹层：我的 → 外观 → 主题颜色。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../data/settings_repository.dart';

Future<void> openThemeColorSheet(
  BuildContext context,
  WidgetRef ref, {
  required ThemeAccent current,
}) async {
  final selected = await showModalBottomSheet<ThemeAccent>(
    context: context,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('主题颜色', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '选一个喜欢的颜色，立刻生效',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 20,
                runSpacing: 16,
                children: [
                  for (final accent in ThemeAccent.values)
                    _AccentSwatch(
                      accent: accent,
                      selected: accent == current,
                      onTap: () => Navigator.of(sheetContext).pop(accent),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  if (selected == null || selected == current) return;

  await ref
      .read(settingsRepositoryProvider)
      .set(SettingKeys.themeAccent, selected.name);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('主题颜色已切换为「${selected.label}」')),
  );
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final ThemeAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.seed,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: theme.colorScheme.onSurface, width: 2)
                  : null,
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 22)
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            accent.label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: selected ? FontWeight.w700 : null,
            ),
          ),
        ],
      ),
    );
  }
}
