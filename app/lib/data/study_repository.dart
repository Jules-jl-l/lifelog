/// 学习模块数据访问层：词库、单词、复习记录、每日统计。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/utils.dart';
import 'db/database.dart';
import 'study/builtin_words.dart';
import 'study/word_import.dart';
import 'study_stats.dart';

class StudyRepository {
  StudyRepository(this._db);

  final AppDatabase _db;

  // ------------------------------------------------------------ 词库
  Stream<List<Wordbook>> watchWordbooks() {
    final query = _db.select(_db.wordbooks)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]);
    return query.watch();
  }

  Future<String> createWordbook({
    required String name,
    String source = 'custom',
    String language = 'en',
  }) async {
    final now = DateTime.now();
    final id = newId();
    await _db.into(_db.wordbooks).insert(
          WordbooksCompanion.insert(
            id: id,
            createdAt: now,
            updatedAt: now,
            name: name,
            source: Value(source),
            language: Value(language),
          ),
        );
    return id;
  }

  Future<void> deleteWordbook(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.wordbooks)..where((t) => t.id.equals(id))).write(
      WordbooksCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await (_db.update(_db.words)
          ..where((t) => t.wordbookId.equals(id) & t.deletedAt.isNull()))
        .write(WordsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }

  Future<void> refreshWordCount(String wordbookId) async {
    final rows = await (_db.select(_db.words)
          ..where((t) => t.wordbookId.equals(wordbookId) & t.deletedAt.isNull()))
        .get();
    await (_db.update(_db.wordbooks)..where((t) => t.id.equals(wordbookId)))
        .write(
      WordbooksCompanion(
        wordCount: Value(rows.length),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ------------------------------------------------------------ 单词
  Stream<List<WordEntry>> watchWords({String? wordbookId}) {
    final query = _db.select(_db.words)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.spelling)]);
    if (wordbookId != null) {
      query.where((t) => t.wordbookId.equals(wordbookId));
    }
    return query.watch().map(
          (rows) => [for (final row in rows) _toEntry(row)],
        );
  }

  Future<void> addWord({
    String? id,
    required String wordbookId,
    required String spelling,
    List<String> meanings = const [],
    List<String> examples = const [],
    String? phoneticUk,
    String? phoneticUs,
  }) async {
    final now = DateTime.now();
    if (id == null) {
      await _db.into(_db.words).insert(
            WordsCompanion.insert(
              id: newId(),
              createdAt: now,
              updatedAt: now,
              wordbookId: wordbookId,
              spelling: spelling,
              phoneticUk: Value(phoneticUk),
              phoneticUs: Value(phoneticUs),
              meaningsJson:
                  Value(meanings.isEmpty ? null : jsonEncode(meanings)),
              examplesJson:
                  Value(examples.isEmpty ? null : jsonEncode(examples)),
            ),
          );
      await refreshWordCount(wordbookId);
      return;
    }

    await (_db.update(_db.words)..where((t) => t.id.equals(id))).write(
      WordsCompanion(
        spelling: Value(spelling),
        phoneticUk: Value(phoneticUk),
        phoneticUs: Value(phoneticUs),
        meaningsJson: Value(meanings.isEmpty ? null : jsonEncode(meanings)),
        examplesJson: Value(examples.isEmpty ? null : jsonEncode(examples)),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> deleteWord(String id) async {
    final now = DateTime.now();
    final row = await (_db.select(_db.words)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    await (_db.update(_db.words)..where((t) => t.id.equals(id))).write(
      WordsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    if (row != null) await refreshWordCount(row.wordbookId);
  }

  /// 单词是否已存在（同一词库内按拼写去重）。
  Future<bool> hasWord(String wordbookId, String spelling) async {
    final row = await (_db.select(_db.words)
          ..where(
            (t) => t.deletedAt.isNull() &
                t.wordbookId.equals(wordbookId) &
                t.spelling.equals(spelling.trim()),
          )
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// 批量导入单词；返回新增与「因重复跳过」的数量。
  ///
  /// 按拼写去重（不区分大小写），与词库中已有单词合并判断。
  Future<({int added, int duplicated})> importWords({
    required String wordbookId,
    required List<ImportedWord> words,
  }) async {
    if (words.isEmpty) return (added: 0, duplicated: 0);

    final existing = await (_db.select(_db.words)
          ..where(
            (t) => t.deletedAt.isNull() & t.wordbookId.equals(wordbookId),
          ))
        .get();
    final known = {
      for (final row in existing) row.spelling.toLowerCase(),
    };

    final now = DateTime.now();
    final rows = <WordsCompanion>[];
    var duplicated = 0;

    for (final word in words) {
      if (!known.add(word.spelling.toLowerCase())) {
        duplicated++;
        continue;
      }
      rows.add(
        WordsCompanion.insert(
          id: newId(),
          createdAt: now,
          updatedAt: now,
          wordbookId: wordbookId,
          spelling: word.spelling,
          phoneticUk: Value(word.phoneticUk),
          phoneticUs: Value(word.phoneticUs),
          meaningsJson: Value(
            word.meanings.isEmpty ? null : jsonEncode(word.meanings),
          ),
          examplesJson: Value(
            word.examples.isEmpty ? null : jsonEncode(word.examples),
          ),
        ),
      );
    }

    if (rows.isNotEmpty) {
      await _db.batch((batch) => batch.insertAll(_db.words, rows));
    }
    await refreshWordCount(wordbookId);

    return (added: rows.length, duplicated: duplicated);
  }

  // ------------------------------------------------------------ 复习记录
  Stream<List<ReviewEntry>> watchReviews() {
    final query = _db.select(_db.reviewRecords)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.reviewedAt)]);
    return query.watch().map(
          (rows) => [
            for (final row in rows)
              ReviewEntry(
                wordId: row.wordId,
                at: row.reviewedAt,
                result: ReviewResult.values.firstWhere(
                  (value) => value.name == row.result,
                  orElse: () => ReviewResult.vague,
                ),
                intervalDays: row.intervalDays,
                ease: row.ease,
                repetitions: row.repetitions,
                nextReviewAt: row.nextReviewAt,
              ),
          ],
        );
  }

  /// 写入一条复习记录，并同步当天统计。
  Future<void> recordReview({
    required String wordId,
    required ReviewResult result,
    required SrsOutcome outcome,
    required bool isNewWord,
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    await _db.into(_db.reviewRecords).insert(
          ReviewRecordsCompanion.insert(
            id: newId(),
            createdAt: now,
            updatedAt: now,
            wordId: wordId,
            reviewedAt: now,
            result: result.name,
            intervalDays: Value(outcome.intervalDays),
            ease: Value(outcome.ease),
            repetitions: Value(outcome.repetitions),
            nextReviewAt: Value(outcome.nextReviewAt),
          ),
        );

    await bumpDailyStat(
      newWords: isNewWord ? 1 : 0,
      reviews: isNewWord ? 0 : 1,
      correct: result.isCorrect,
    );
  }

  // ------------------------------------------------------------ 每日统计
  Stream<List<StudyStatEntry>> watchStats(DateTime from, DateTime to) {
    final query = _db.select(_db.studyStats)
      ..where(
        (t) => t.deletedAt.isNull() &
            t.statDate.isBiggerOrEqualValue(formatDate(from)) &
            t.statDate.isSmallerOrEqualValue(formatDate(to)),
      )
      ..orderBy([(t) => OrderingTerm(expression: t.statDate)]);
    return query.watch().map(
          (rows) => [
            for (final row in rows)
              StudyStatEntry(
                statDate: row.statDate,
                newCount: row.newCount,
                reviewCount: row.reviewCount,
                correctRate: row.correctRate,
                durationSec: row.durationSec,
              ),
          ],
        );
  }

  /// 累加当天的学习量。正确率按「历史总量 × 旧正确率 + 本次」重算，避免精度损失。
  Future<void> bumpDailyStat({
    int newWords = 0,
    int reviews = 0,
    bool? correct,
    int durationSec = 0,
  }) async {
    final today = formatDate(DateTime.now());
    final existing = await (_db.select(_db.studyStats)
          ..where((t) => t.deletedAt.isNull() & t.statDate.equals(today)))
        .getSingleOrNull();

    final oldNew = existing?.newCount ?? 0;
    final oldReviews = existing?.reviewCount ?? 0;
    final oldTotal = oldNew + oldReviews;
    final oldCorrect = (existing?.correctRate ?? 0) * oldTotal;

    final newCount = oldNew + newWords;
    final reviewCount = oldReviews + reviews;
    final total = newCount + reviewCount;
    final correctCount = oldCorrect + (correct == true ? 1 : 0);
    final correctRate = total == 0 ? 0.0 : correctCount / total;
    final duration = (existing?.durationSec ?? 0) + durationSec;

    final now = DateTime.now();
    if (existing == null) {
      await _db.into(_db.studyStats).insert(
            StudyStatsCompanion.insert(
              id: newId(),
              createdAt: now,
              updatedAt: now,
              statDate: today,
              newCount: Value(newCount),
              reviewCount: Value(reviewCount),
              correctRate: Value(correctRate),
              durationSec: Value(duration),
            ),
          );
      return;
    }

    await (_db.update(_db.studyStats)
          ..where((t) => t.id.equals(existing.id)))
        .write(
      StudyStatsCompanion(
        newCount: Value(newCount),
        reviewCount: Value(reviewCount),
        correctRate: Value(correctRate),
        durationSec: Value(duration),
        updatedAt: Value(now),
      ),
    );
  }

  // ------------------------------------------------------------ Future 版本（供 AI 工具使用）
  Future<List<Wordbook>> wordbooksOnce() async {
    return (_db.select(_db.wordbooks)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
  }

  /// 按名称查找词库：先精确（忽略大小写），再模糊包含。
  Future<Wordbook?> findWordbookByName(String name) async {
    final target = name.trim().toLowerCase();
    if (target.isEmpty) return null;
    final books = await wordbooksOnce();
    for (final book in books) {
      if (book.name.toLowerCase() == target) return book;
    }
    for (final book in books) {
      if (book.name.toLowerCase().contains(target)) return book;
    }
    return null;
  }

  Future<List<WordEntry>> wordsOnce({String? wordbookId}) async {
    final query = _db.select(_db.words)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.spelling)]);
    if (wordbookId != null) {
      query.where((t) => t.wordbookId.equals(wordbookId));
    }
    final rows = await query.get();
    return [for (final row in rows) _toEntry(row)];
  }

  Future<List<ReviewEntry>> reviewsOnce() async {
    final rows = await (_db.select(_db.reviewRecords)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.reviewedAt)]))
        .get();
    return [
      for (final row in rows)
        ReviewEntry(
          wordId: row.wordId,
          at: row.reviewedAt,
          result: ReviewResult.values.firstWhere(
            (value) => value.name == row.result,
            orElse: () => ReviewResult.vague,
          ),
          intervalDays: row.intervalDays,
          ease: row.ease,
          repetitions: row.repetitions,
          nextReviewAt: row.nextReviewAt,
        ),
    ];
  }

  Future<List<StudyStatEntry>> statsOnce(DateTime from, DateTime to) async {
    final rows = await (_db.select(_db.studyStats)
          ..where(
            (t) => t.deletedAt.isNull() &
                t.statDate.isBiggerOrEqualValue(formatDate(from)) &
                t.statDate.isSmallerOrEqualValue(formatDate(to)),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.statDate)]))
        .get();
    return [
      for (final row in rows)
        StudyStatEntry(
          statDate: row.statDate,
          newCount: row.newCount,
          reviewCount: row.reviewCount,
          correctRate: row.correctRate,
          durationSec: row.durationSec,
        ),
    ];
  }

  // ------------------------------------------------------------ 初始化
  /// 首次启动时写入内置词库（幂等）。
  Future<void> ensureBuiltinWordbook() async {
    final existing = await (_db.select(_db.wordbooks)
          ..where(
            (t) => t.deletedAt.isNull() & t.name.equals(builtinWordbookName),
          )
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) return;

    final now = DateTime.now();
    final bookId = newId();
    await _db.into(_db.wordbooks).insert(
          WordbooksCompanion.insert(
            id: bookId,
            createdAt: now,
            updatedAt: now,
            name: builtinWordbookName,
            source: const Value('builtin'),
            wordCount: Value(builtinCet4.length),
          ),
        );

    await _db.batch((batch) {
      batch.insertAll(_db.words, [
        for (final word in builtinCet4)
          WordsCompanion.insert(
            id: newId(),
            createdAt: now,
            updatedAt: now,
            wordbookId: bookId,
            spelling: word.spelling,
            phoneticUk: Value(word.phoneticUk),
            phoneticUs: Value(word.phoneticUs),
            meaningsJson: Value(jsonEncode(word.meanings)),
            examplesJson: Value(
              word.example == null ? null : jsonEncode([word.example]),
            ),
          ),
      ]);
    });
  }

  WordEntry _toEntry(Word row) => WordEntry(
        id: row.id,
        wordbookId: row.wordbookId,
        spelling: row.spelling,
        phoneticUk: row.phoneticUk,
        phoneticUs: row.phoneticUs,
        meanings: _decodeList(row.meaningsJson),
        examples: _decodeList(row.examplesJson),
        tags: _decodeList(row.tags),
      );

  List<String> _decodeList(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return [
          for (final item in decoded)
            if (item is String) item,
        ];
      }
    } on FormatException {
      // 数据损坏时按空处理，不让页面崩掉
    }
    return const [];
  }
}
