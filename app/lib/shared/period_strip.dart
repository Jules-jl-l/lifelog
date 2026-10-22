/// 周 / 月 / 年周期横滑选择条：财务与健康共用。
///
/// 注意：滚动定位只作用于周期条自身的 [Scrollable]，
/// 不要用全局 [Scrollable.ensureVisible]，否则会带动外层纵向列表。
library;

import 'package:flutter/material.dart';

import '../core/period.dart';

class PeriodStrip extends StatefulWidget {
  const PeriodStrip({
    super.key,
    required this.options,
    required this.selectedKey,
    required this.onSelected,
  });

  final List<PeriodOption> options;
  final String selectedKey;
  final ValueChanged<PeriodOption> onSelected;

  @override
  State<PeriodStrip> createState() => _PeriodStripState();
}

class _PeriodStripState extends State<PeriodStrip> {
  final _controller = ScrollController();
  final _keys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(jump: true));
  }

  @override
  void didUpdateWidget(covariant PeriodStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedKey != widget.selectedKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reveal({bool jump = false}) {
    if (!mounted) return;
    final target = _keys[widget.selectedKey]?.currentContext;
    final renderObject = target?.findRenderObject();
    if (target == null || renderObject == null) return;
    // 只滚动周期条自身，避免影响外层纵向列表。
    final scrollable = Scrollable.maybeOf(target);
    if (scrollable == null) return;
    scrollable.position.ensureVisible(
      renderObject,
      alignment: 0.5,
      duration: jump ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 大字体下加高，避免周期标签被上下裁切。
    final textScale =
        MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return Container(
      height: 46 + (textScale - 1) * 18,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final option in widget.options)
              _PeriodTab(
                key: _keys.putIfAbsent(option.key, () => GlobalKey()),
                label: option.label,
                selected: option.key == widget.selectedKey,
                onTap: () => widget.onSelected(option),
              ),
          ],
        ),
      ),
    );
  }
}

class _PeriodTab extends StatelessWidget {
  const _PeriodTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        selected ? theme.colorScheme.primary : theme.colorScheme.outline;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: selected ? theme.colorScheme.primary : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: theme.textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
