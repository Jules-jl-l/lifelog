/// CSV 导出：纯格式化函数 + 从本地库生成导出文件。
library;

import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils.dart';
import '../db/database.dart';
import '../study/quiz.dart';

enum ExportKind { transactions, weight, measure, workout, study, quiz }

extension ExportKindLabel on ExportKind {
  String get label => switch (this) {
        ExportKind.transactions => '流水',
        ExportKind.weight => '体重',
        ExportKind.measure => '围度',
        ExportKind.workout => '运动',
        ExportKind.study => '学习统计',
        ExportKind.quiz => '测验记录',
      };
}

class ExportedCsv {
  const ExportedCsv({
    required this.kind,
    required this.fileName,
    required this.content,
  });

  final ExportKind kind;
  final String fileName;
  final String content;
}

/// CSV 字段转义：含逗号、引号、换行时用双引号包裹。
String csvField(Object? value) {
  final text = value?.toString() ?? '';
  if (!text.contains(RegExp(r'[",\r\n]'))) return text;
  return '"${text.replaceAll('"', '""')}"';
}

/// 生成带 UTF-8 BOM 的 CSV 文档，换行用 CRLF 以兼容 Excel。
String csvDocument(List<String> header, Iterable<List<Object?>> rows) {
  final buffer = StringBuffer('\uFEFF');
  buffer.write(header.map(csvField).join(','));
  buffer.write('\r\n');
  for (final row in rows) {
    buffer.write(row.map(csvField).join(','));
    buffer.write('\r\n');
  }
  return buffer.toString();
}

String _yuan(int cents) => (cents / 100).toStringAsFixed(2);

String _stamp(DateTime value) {
  String pad(int input) => input.toString().padLeft(2, '0');
  return '${value.year}${pad(value.month)}${pad(value.day)}'
      '-${pad(value.hour)}${pad(value.minute)}${pad(value.second)}';
}

class ExportService {
  ExportService(this._db);

  final AppDatabase _db;

  /// 生成所选数据集的 CSV 内容。
  Future<List<ExportedCsv>> build(
    Set<ExportKind> kinds, {
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    final stamp = _stamp(now);
    final files = <ExportedCsv>[];

    if (kinds.contains(ExportKind.transactions)) {
      final rows = await (_db.select(_db.transactions)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.occurredAt)]))
          .get();
      final accounts = {for (final row in await _db.select(_db.accounts).get()) row.id: row.name};
      final categories = {
        for (final row in await _db.select(_db.categories).get())
          row.id: row.name,
      };
      files.add(
        ExportedCsv(
          kind: ExportKind.transactions,
          fileName: 'lifelog-transactions-$stamp.csv',
          content: csvDocument(
            const ['日期', '类型', '金额(元)', '分类', '账户', '商户', '备注', '来源'],
            [
              for (final row in rows)
                [
                  formatDateTime(row.occurredAt),
                  row.kind.label,
                  _yuan(row.amount),
                  categories[row.categoryId] ?? '',
                  accounts[row.accountId] ?? '',
                  row.payee ?? '',
                  row.note ?? '',
                  row.source.label,
                ],
            ],
          ),
        ),
      );
    }

    if (kinds.contains(ExportKind.weight)) {
      final rows = await (_db.select(_db.weightRecords)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.recordedAt)]))
          .get();
      files.add(
        ExportedCsv(
          kind: ExportKind.weight,
          fileName: 'lifelog-weight-$stamp.csv',
          content: csvDocument(
            const ['日期', '体重(kg)', '体脂率(%)', '备注'],
            [
              for (final row in rows)
                [
                  formatDateTime(row.recordedAt),
                  (row.weightGrams / 1000).toStringAsFixed(2),
                  row.bodyFatPct?.toStringAsFixed(1) ?? '',
                  row.note ?? '',
                ],
            ],
          ),
        ),
      );
    }

    if (kinds.contains(ExportKind.measure)) {
      final rows = await (_db.select(_db.bodyMeasures)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.measuredAt)]))
          .get();
      files.add(
        ExportedCsv(
          kind: ExportKind.measure,
          fileName: 'lifelog-measure-$stamp.csv',
          content: csvDocument(
            const ['日期', '部位', '数值(cm)', '备注'],
            [
              for (final row in rows)
                [
                  formatDateTime(row.measuredAt),
                  row.part,
                  (row.valueMm / 10).toStringAsFixed(1),
                  row.note ?? '',
                ],
            ],
          ),
        ),
      );
    }

    if (kinds.contains(ExportKind.workout)) {
      final rows = await (_db.select(_db.workouts)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.startedAt)]))
          .get();
      files.add(
        ExportedCsv(
          kind: ExportKind.workout,
          fileName: 'lifelog-workout-$stamp.csv',
          content: csvDocument(
            const ['日期', '类型', '时长(分钟)', '距离(km)', '消耗(kcal)', '平均心率', '备注'],
            [
              for (final row in rows)
                [
                  formatDateTime(row.startedAt),
                  row.type,
                  row.durationMin,
                  row.distanceM == null
                      ? ''
                      : (row.distanceM! / 1000).toStringAsFixed(2),
                  row.calories ?? '',
                  row.avgHr ?? '',
                  row.note ?? '',
                ],
            ],
          ),
        ),
      );
    }

    if (kinds.contains(ExportKind.study)) {
      final rows = await (_db.select(_db.studyStats)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.statDate)]))
          .get();
      files.add(
        ExportedCsv(
          kind: ExportKind.study,
          fileName: 'lifelog-study-$stamp.csv',
          content: csvDocument(
            const ['日期', '新词', '复习', '正确率(%)', '用时(秒)'],
            [
              for (final row in rows)
                [
                  row.statDate,
                  row.newCount,
                  row.reviewCount,
                  (row.correctRate * 100).toStringAsFixed(0),
                  row.durationSec,
                ],
            ],
          ),
        ),
      );
    }

    if (kinds.contains(ExportKind.quiz)) {
      final rows = await (_db.select(_db.quizSessions)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .get();
      final books = {
        for (final row in await _db.select(_db.wordbooks).get()) row.id: row.name,
      };
      files.add(
        ExportedCsv(
          kind: ExportKind.quiz,
          fileName: 'lifelog-quiz-$stamp.csv',
          content: csvDocument(
            const ['时间', '词库', '模式', '题数', '正确数', '正确率(%)', '用时(秒)'],
            [
              for (final row in rows)
                [
                  formatDateTime(row.createdAt),
                  books[row.wordbookId] ?? '全部',
                  QuizModeLabel.fromStorage(row.mode).label,
                  row.total,
                  row.correct,
                  row.total == 0
                      ? '0'
                      : (row.correct / row.total * 100).toStringAsFixed(0),
                  row.durationSec,
                ],
            ],
          ),
        ),
      );
    }

    return files;
  }

  /// 把 CSV 写入应用文档目录，返回文件列表。
  Future<List<File>> writeToFiles(List<ExportedCsv> files) async {
    final dir = await getApplicationDocumentsDirectory();
    final result = <File>[];
    for (final item in files) {
      final file = File(p.join(dir.path, item.fileName));
      await file.writeAsString(item.content, flush: true);
      result.add(file);
    }
    return result;
  }
}
