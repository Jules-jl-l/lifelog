/// 本地规则记账解析器：完全离线可用。
///
/// 覆盖「午饭 30」「打车 15」「工资到账 8000」这类高频简单指令，
/// 在无外网或没配 API Key 时兜底，不让记账断掉。
library;

import '../db/database.dart';

class ParsedTransaction {
  const ParsedTransaction({
    required this.kind,
    required this.amount,
    this.categoryName,
    this.payee,
  });

  final TxnKind kind;

  /// 分
  final int amount;
  final String? categoryName;
  final String? payee;
}

/// 关键词 -> 分类名；顺序即优先级（更具体的词写在前面）。
const _categoryKeywords = <String, String>{
  '早饭': '餐饮',
  '午饭': '餐饮',
  '午餐': '餐饮',
  '晚饭': '餐饮',
  '晚餐': '餐饮',
  '外卖': '餐饮',
  '咖啡': '餐饮',
  '奶茶': '餐饮',
  '零食': '餐饮',
  '食堂': '餐饮',
  '吃': '餐饮',
  '打车': '交通',
  '地铁': '交通',
  '公交': '交通',
  '加油': '交通',
  '高铁': '交通',
  '火车': '交通',
  '停车': '交通',
  '超市': '购物',
  '买菜': '购物',
  '淘宝': '购物',
  '京东': '购物',
  '衣服': '购物',
  '购物': '购物',
  '房租': '居住',
  '水电': '居住',
  '物业': '居住',
  '医院': '医疗',
  '挂号': '医疗',
  '买药': '医疗',
  '电影': '娱乐',
  '游戏': '娱乐',
  '健身': '运动',
  '工资': '工资',
  '入账': '工资',
};

const _incomeKeywords = ['工资', '入账', '到账', '收入', '收到', '报销', '退款', '红包', '进账'];

final _amountPattern = RegExp(r'(\d+(?:\.\d{1,2})?)');
final _unitPattern = RegExp(r'[元块钱]');

/// 尝试把一句自然语言解析成一笔记账；无法识别时返回 null。
ParsedTransaction? parseBookkeeping(String text) {
  final input = text.trim();
  if (input.isEmpty) return null;

  final match = _amountPattern.firstMatch(input);
  if (match == null) return null;

  final yuan = double.tryParse(match.group(1)!);
  if (yuan == null || yuan <= 0) return null;

  final isIncome = _incomeKeywords.any(input.contains);
  final kind = isIncome ? TxnKind.income : TxnKind.expense;

  String? category;
  for (final entry in _categoryKeywords.entries) {
    if (input.contains(entry.key)) {
      category = entry.value;
      break;
    }
  }
  if (isIncome && category == null) category = '工资';

  final payee = input
      .replaceAll(match.group(0)!, '')
      .replaceAll(_unitPattern, '')
      .trim();

  return ParsedTransaction(
    kind: kind,
    amount: (yuan * 100).round(),
    categoryName: category,
    payee: payee.isEmpty ? null : payee,
  );
}
