/// 金额计算器弹层：数字、小数点、四则运算、删除与清空，点「完成」回填结果。
library;

import 'package:flutter/material.dart';

import '../core/amount_calculator.dart';

/// 打开金额计算器；用户取消时返回 null，完成后返回两位小数的金额字符串。
Future<String?> showAmountCalculator(
  BuildContext context, {
  String? initialValue,
  String title = '金额计算',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => AmountCalculatorSheet(
      initialValue: initialValue,
      title: title,
    ),
  );
}

class AmountCalculatorSheet extends StatefulWidget {
  const AmountCalculatorSheet({
    super.key,
    this.initialValue,
    this.title = '金额计算',
  });

  final String? initialValue;
  final String title;

  @override
  State<AmountCalculatorSheet> createState() => _AmountCalculatorSheetState();
}

class _AmountCalculatorSheetState extends State<AmountCalculatorSheet> {
  late String _expression = _sanitize(widget.initialValue ?? '');

  static String _sanitize(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    // 只保留数字、小数点和四则运算符，避免把外部格式带进来
    final buffer = StringBuffer();
    for (final char in trimmed.split('')) {
      if (RegExp(r'[0-9.+\-×÷]').hasMatch(char)) buffer.write(char);
    }
    return buffer.toString();
  }

  bool get _canSubmit => evaluateAmountExpression(_expression) != null;

  String get _resultLabel {
    final value = evaluateAmountExpression(_expression);
    if (value == null) return _expression.isEmpty ? '0.00' : '表达式不完整';
    return formatCalculatorResult(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.title, style: theme.textTheme.titleMedium),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _expression.isEmpty ? '0' : _expression,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '= ¥$_resultLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _canSubmit
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _row(const ['7', '8', '9', '⌫']),
          _row(const ['4', '5', '6', '清空']),
          _row(const ['1', '2', '3', '+']),
          _row(const ['0', '.', '×', '-']),
          Row(
            children: [
              Expanded(
                child: _KeyButton(
                  key: const ValueKey('calc-÷'),
                  label: '÷',
                  onTap: () => _append('÷'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: _KeyButton(
                  key: const ValueKey('calc-完成'),
                  label: '完成',
                  filled: true,
                  onTap: _canSubmit ? _submit : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(List<String> keys) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          for (var index = 0; index < keys.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            Expanded(
              child: _KeyButton(
                key: ValueKey('calc-${keys[index]}'),
                label: keys[index],
                onTap: () => _onKey(keys[index]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _onKey(String key) {
    switch (key) {
      case '⌫':
        _backspace();
      case '清空':
        setState(() => _expression = '');
      case '.':
        _appendDecimal();
      default:
        _append(key);
    }
  }

  void _append(String key) {
    setState(() {
      if (_expression.isEmpty) {
        if (key == '.') {
          _expression = '0.';
        } else if (RegExp(r'[0-9]').hasMatch(key)) {
          _expression = key;
        }
        return;
      }

      final last = _expression[_expression.length - 1];
      final isOperator = '+-×÷'.contains(last);

      if (RegExp(r'[0-9]').hasMatch(key)) {
        _expression += key;
        return;
      }

      if ('+-×÷'.contains(key)) {
        if (last == '.') {
          _expression = '${_expression.substring(0, _expression.length - 1)}$key';
        } else if (isOperator) {
          _expression =
              '${_expression.substring(0, _expression.length - 1)}$key';
        } else {
          _expression += key;
        }
      }
    });
  }

  void _appendDecimal() {
    setState(() {
      if (_expression.isEmpty) {
        _expression = '0.';
        return;
      }
      // 小数点只能出现在当前数字里
      var segmentStart = 0;
      for (var index = _expression.length - 1; index >= 0; index--) {
        if ('+-×÷'.contains(_expression[index])) {
          segmentStart = index + 1;
          break;
        }
      }
      final segment = _expression.substring(segmentStart);
      if (segment.contains('.')) return;
      if (segment.isEmpty) {
        _expression += '0.';
      } else {
        _expression += '.';
      }
    });
  }

  void _backspace() {
    if (_expression.isEmpty) return;
    setState(() {
      _expression = _expression.substring(0, _expression.length - 1);
    });
  }

  void _submit() {
    final value = evaluateAmountExpression(_expression);
    if (value == null) return;
    Navigator.of(context).pop(formatCalculatorResult(value));
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = filled
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final foreground = filled
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    return SizedBox(
      height: 52,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                color: onTap == null
                    ? theme.colorScheme.outline
                    : foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
