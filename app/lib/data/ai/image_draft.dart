/// 通用截图识别结果：支付账单 / 体重 / 围度。
///
/// 与 ReceiptDraft 分开存放：识图入口先判断截图类型，再交给对应确认表单。
library;

import 'dart:convert';

import 'receipt_draft.dart';

enum ImageDraftType { transaction, weight, measure, unknown }

/// 交给多模态模型的通用识别指令。
const imageExtractionInstruction =
    '这是一张手机截图，可能是支付账单、体重记录（体重秤/健康 App）或身体围度记录。\n'
    '先判断截图类型，然后只输出 JSON，不要任何多余文字：\n'
    '{"type": "transaction" 或 "weight" 或 "measure" 或 "unknown", '
    '"confidence": 0 到 1 之间的置信度,\n'
    ' 支付类补充: "amount": 数字(单位元), "direction": "expense" 或 "income", '
    '"payee": "商户或对方", "occurred_at": "YYYY-MM-DD HH:mm", '
    '"channel": "微信/支付宝/银行卡/其他", "trade_no": "交易单号", '
    '"category": "分类建议(餐饮/交通/购物/居住/医疗/娱乐/工资等)",\n'
    ' 体重类补充: "weight_kg": 数字, "body_fat_pct": 数字或 null, '
    '"measured_at": "YYYY-MM-DD HH:mm",\n'
    ' 围度类补充: "measures": [{"part": "腰围", "cm": 78.5}], '
    '"measured_at": "YYYY-MM-DD HH:mm"}\n'
    '识别不到的字段用 null。';

class MeasurePoint {
  const MeasurePoint({required this.part, required this.mm});

  final String part;

  /// 毫米
  final int mm;

  Map<String, dynamic> toJson() => {'part': part, 'mm': mm};

  static MeasurePoint? fromJson(Map<String, dynamic> json) {
    final part = json['part'];
    final mm = (json['mm'] as num?)?.toInt();
    if (part is! String || part.trim().isEmpty || mm == null || mm <= 0) {
      return null;
    }
    return MeasurePoint(part: part.trim(), mm: mm);
  }
}

class ImageDraft {
  ImageDraft({
    required this.type,
    required this.confidence,
    this.receipt,
    this.weightGrams,
    this.bodyFatPct,
    this.measuredAt,
    this.measures = const [],
  });

  final ImageDraftType type;
  final double confidence;

  /// 支付截图对应的草稿。
  final ReceiptDraft? receipt;

  /// 体重（克）。
  final int? weightGrams;
  final double? bodyFatPct;

  /// 记录时间（体重 / 围度）。
  final DateTime? measuredAt;
  final List<MeasurePoint> measures;

  bool get isUsable => switch (type) {
        ImageDraftType.transaction => receipt != null,
        ImageDraftType.weight => (weightGrams ?? 0) > 0,
        ImageDraftType.measure => measures.isNotEmpty,
        ImageDraftType.unknown => false,
      };

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'confidence': confidence,
        'receipt': receipt?.toJson(),
        'weightGrams': weightGrams,
        'bodyFatPct': bodyFatPct,
        'measuredAt': measuredAt?.toIso8601String(),
        'measures': [for (final point in measures) point.toJson()],
      };

  static ImageDraft? fromJson(Map<String, dynamic> json) {
    final type = ImageDraftType.values.firstWhere(
      (item) => item.name == json['type'],
      orElse: () => ImageDraftType.unknown,
    );
    final receiptJson = json['receipt'];
    final receipt = receiptJson is Map<String, dynamic>
        ? ReceiptDraft.fromJson(receiptJson)
        : null;

    return ImageDraft(
      type: type,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      receipt: receipt,
      weightGrams: (json['weightGrams'] as num?)?.toInt(),
      bodyFatPct: (json['bodyFatPct'] as num?)?.toDouble(),
      measuredAt: json['measuredAt'] is String
          ? DateTime.tryParse(json['measuredAt'] as String)
          : null,
      measures: [
        for (final item in (json['measures'] as List<dynamic>? ?? const []))
          if (item is Map<String, dynamic>) ?MeasurePoint.fromJson(item),
      ],
    );
  }

  /// 从模型输出解析（容忍 ```json 包裹）。
  static ImageDraft? fromModelOutput(String raw) {
    final json = _extractJson(raw);
    if (json == null) return null;

    final typeName = (json['type'] as String?)?.toLowerCase();
    final type = switch (typeName) {
      'transaction' => ImageDraftType.transaction,
      'weight' => ImageDraftType.weight,
      'measure' => ImageDraftType.measure,
      _ => ImageDraftType.unknown,
    };

    final confidence = (json['confidence'] as num?)?.toDouble() ?? 0.5;
    final at = _parseTime(json['measured_at'] ?? json['occurred_at']);

    switch (type) {
      case ImageDraftType.transaction:
        final receipt = ReceiptDraft.fromModelOutput(raw);
        if (receipt == null) return null;
        return ImageDraft(
          type: type,
          confidence: confidence,
          receipt: receipt,
        );
      case ImageDraftType.weight:
        final kg = (json['weight_kg'] as num?)?.toDouble();
        if (kg == null || kg <= 0) return null;
        return ImageDraft(
          type: type,
          confidence: confidence,
          weightGrams: (kg * 1000).round(),
          bodyFatPct: (json['body_fat_pct'] as num?)?.toDouble(),
          measuredAt: at,
        );
      case ImageDraftType.measure:
        final points = <MeasurePoint>[];
        final rawMeasures = json['measures'];
        if (rawMeasures is List) {
          for (final item in rawMeasures) {
            if (item is! Map<String, dynamic>) continue;
            final part = item['part'];
            final cm = (item['cm'] as num?)?.toDouble();
            if (part is! String || part.trim().isEmpty || cm == null || cm <= 0) {
              continue;
            }
            points.add(
              MeasurePoint(part: part.trim(), mm: (cm * 10).round()),
            );
          }
        }
        // 兼容模型只返回单个 part/cm 的情况
        final singlePart = json['part'];
        final singleCm = (json['cm'] as num?)?.toDouble();
        if (points.isEmpty &&
            singlePart is String &&
            singlePart.trim().isNotEmpty &&
            singleCm != null &&
            singleCm > 0) {
          points.add(
            MeasurePoint(part: singlePart.trim(), mm: (singleCm * 10).round()),
          );
        }
        if (points.isEmpty) return null;
        return ImageDraft(
          type: type,
          confidence: confidence,
          measuredAt: at,
          measures: points,
        );
      case ImageDraftType.unknown:
        return ImageDraft(type: type, confidence: confidence);
    }
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

  static DateTime? _parseTime(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
}
