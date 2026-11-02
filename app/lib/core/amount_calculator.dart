/// 金额计算器：解析 `+ - × ÷` 表达式，按先乘除后加减求值。
///
/// 只服务于金额输入框，不引入完整表达式引擎；表达式不完整或除以 0 时返回 null。
library;

/// 把界面上的 `×` / `÷` 归一化成 ASCII 运算符。
String normalizeAmountExpression(String expression) =>
    expression.replaceAll('×', '*').replaceAll('÷', '/');

/// 求值；表达式不完整、含非法字符或出现除以 0 时返回 null。
double? evaluateAmountExpression(String expression) {
  final input = normalizeAmountExpression(expression).replaceAll(' ', '');
  if (input.isEmpty) return null;

  final numbers = <double>[];
  final operators = <String>[];
  var start = 0;

  for (var index = 0; index <= input.length; index++) {
    final atEnd = index == input.length;
    final char = atEnd ? null : input[index];
    final isOperator = char != null && '+-*/'.contains(char);

    if (!atEnd && !isOperator) {
      final code = char?.codeUnitAt(0) ?? -1;
      final isDigit = code >= 48 && code <= 57;
      if (!isDigit && char != '.') return null;
      continue;
    }

    // 开头就是运算符，或出现连续运算符
    if (start == index) return null;
    final value = double.tryParse(input.substring(start, index));
    if (value == null) return null;
    numbers.add(value);
    if (isOperator) operators.add(char);
    start = index + 1;
  }

  if (numbers.length != operators.length + 1) return null;

  var total = 0.0;
  var pendingAdd = '+';
  var term = numbers.first;

  for (var index = 0; index < operators.length; index++) {
    final operator = operators[index];
    final next = numbers[index + 1];

    if (operator == '*' || operator == '/') {
      if (operator == '/' && next == 0) return null;
      term = operator == '*' ? term * next : term / next;
      continue;
    }

    total = _combine(total, pendingAdd, term);
    pendingAdd = operator;
    term = next;
  }

  total = _combine(total, pendingAdd, term);
  if (total.isNaN || total.isInfinite) return null;
  return total;
}

/// 求值并换算成分；无效表达式返回 null。
int? evaluateAmountExpressionToCents(String expression) {
  final value = evaluateAmountExpression(expression);
  if (value == null) return null;
  return (value * 100).round();
}

/// 计算结果回填到金额输入框时的展示格式：固定两位小数。
String formatCalculatorResult(double value) => value.toStringAsFixed(2);

double _combine(double left, String operator, double right) =>
    operator == '-' ? left - right : left + right;
