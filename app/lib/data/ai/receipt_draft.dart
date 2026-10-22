/// 结构化的识图结果（支付截图）。
///
/// 放在数据层，便于队列重放时直接复用；UI 只负责展示与确认。
library;

import 'dart:convert';

import '../db/database.dart';

/// 交给多模态模型的提取指令。
const receiptExtractionInstruction =
    '这是一张支付截图。请提取下列字段，只输出 JSON，不要任何多余文字：\n'
    '{"amount": 数字(单位元), "direction": "expense" 或 "income", "payee": "商户或对方", '
    '"occurred_at": "YYYY-MM-DD HH:mm", "channel": "微信/支付宝/银行卡/其他", '
    '"trade_no": "交易单号", "category": "分类建议(餐饮/交通/购物/居住/医疗/娱乐/工资等)", '
    '"confidence": 0 到 1 之间的置信度}\n'
    '识别不到的字段用 null。';

class ReceiptDraft {
  ReceiptDraft({
    required this.amount,
    required this.kind,
    required this.confidence,
    this.payee,
    this.categoryName,
    this.occurredAt,
    this.channel,
    this.tradeNo,
  });

  /// 分
  int amount;
  TxnKind kind;
  double confidence;
  String? payee;
  String? categoryName;
  DateTime? occurredAt;
  String? channel;
  String? tradeNo;

  /// 去重指纹：优先用交易单号，否则用「金额 + 时间 + 商户」。
  String? get fingerprint {
    if (tradeNo != null && tradeNo!.isNotEmpty) return tradeNo;
    final at = occurredAt ?? DateTime.now();
    final stamp = '${at.year}-${at.month}-${at.day} '
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    return '$amount|$stamp|${payee ?? ''}';
  }

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'kind': kind.name,
        'confidence': confidence,
        'payee': payee,
        'category': categoryName,
        'occurredAt': occurredAt?.toIso8601String(),
        'channel': channel,
        'tradeNo': tradeNo,
      };

  static ReceiptDraft? fromJson(Map<String, dynamic> json) {
    final amount = (json['amount'] as num?)?.toInt();
    if (amount == null || amount <= 0) return null;

    return ReceiptDraft(
      amount: amount,
      kind: json['kind'] == TxnKind.income.name
          ? TxnKind.income
          : TxnKind.expense,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      payee: _clean(json['payee']),
      categoryName: _clean(json['category']),
      occurredAt: json['occurredAt'] is String
          ? DateTime.tryParse(json['occurredAt'] as String)
          : null,
      channel: _clean(json['channel']),
      tradeNo: _clean(json['tradeNo']),
    );
  }

  /// 从模型输出里解析 JSON（容忍 ```json 代码块包裹）。
  static ReceiptDraft? fromModelOutput(String raw) {
    final json = _extractJson(raw);
    if (json == null) return null;

    final amountYuan = (json['amount'] as num?)?.toDouble();
    if (amountYuan == null || amountYuan <= 0) return null;

    final direction = (json['direction'] as String?)?.toLowerCase();
    return ReceiptDraft(
      amount: (amountYuan * 100).round(),
      kind: direction == 'income' ? TxnKind.income : TxnKind.expense,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      payee: _clean(json['payee']),
      categoryName: _clean(json['category']),
      occurredAt: _parseTime(json['occurred_at']),
      channel: _clean(json['channel']),
      tradeNo: _clean(json['trade_no']),
    );
  }

  static Map<String, dynamic>? _extractJson(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String? _clean(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return null;
    return trimmed;
  }

  static DateTime? _parseTime(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
}
