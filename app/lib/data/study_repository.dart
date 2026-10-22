/// 学习模块数据访问层：词库、单词、复习记录、每日统计。
library;

import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../core/utils.dart';
import 'db/database.dart';
import 'study/builtin_wordbooks.dart';
import 'study/quiz.dart';
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
  bool _builtinReady = false;
  Future<void>? _builtinSeeding;

  /// 首次启动时写入内置词库（幂等）。
  ///
  /// 资源含 CET-4 / CET-6 / 考研英语 / IT 行业必备词汇。
  /// 旧版本的「CET-4 核心词」会被复用并补齐为完整 CET-4，避免出现两本重复词库。
  Future<void> ensureBuiltinWordbooks({
    List<BuiltinWordbookData>? books,
  }) {
    if (_builtinReady) return Future.value();
    return _builtinSeeding ??= _seedBuiltinWordbooks(books)
        .then((_) => _builtinReady = true)
        .whenComplete(() => _builtinSeeding = null);
  }

  Future<void> ensureBuiltinWordbook() => ensureBuiltinWordbooks();

  Future<void> _seedBuiltinWordbooks(
    List<BuiltinWordbookData>? books,
  ) async {
    final data = books ?? await loadBuiltinWordbooks();
    // 包含软删除记录：用户删除内置词库后，重启不应再次自动重建。
    final existing = await _db.select(_db.wordbooks).get();

    for (final bookData in data) {
      Wordbook? found = existing
          .where((book) => book.name == bookData.name)
          .firstOrNull;
      if (found == null && bookData.slug == 'cet4') {
        found = existing
            .where((book) => book.name == legacyBuiltinWordbookName)
            .firstOrNull;
      }

      // 词库已被用户删除：保留在回收站，等待用户恢复或彻底删除。
      if (found != null && found.deletedAt != null) continue;

      if (found == null) {
        final id = await createWordbook(
          name: bookData.name,
          source: 'builtin',
        );
        await _insertBuiltinWords(id, bookData.words);
        continue;
      }

      final book = found;
      final rows = await (_db.select(_db.words)
            ..where(
              (t) => t.wordbookId.equals(book.id) & t.deletedAt.isNull(),
            ))
          .get();
      final known = {for (final row in rows) row.spelling.toLowerCase()};
      final missing = [
        for (final word in bookData.words)
          if (known.add(word.spelling.toLowerCase())) word,
      ];
      if (missing.isNotEmpty) {
        await _insertBuiltinWords(book.id, missing);
      }
      if (bookData.slug == 'cet4' && book.name == legacyBuiltinWordbookName) {
        await (_db.update(_db.wordbooks)..where((t) => t.id.equals(book.id)))
            .write(
          WordbooksCompanion(
            name: Value(bookData.name),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    }
  }

  Future<void> _insertBuiltinWords(
    String wordbookId,
    List<BuiltinWordData> words,
  ) async {
    if (words.isEmpty) return;
    final now = DateTime.now();
    const chunkSize = 200;
    for (var start = 0; start < words.length; start += chunkSize) {
      final slice = words.sublist(
        start,
        min(start + chunkSize, words.length),
      );
      await _db.batch(
        (batch) => batch.insertAll(_db.words, [
          for (final word in slice)
            WordsCompanion.insert(
              id: newId(),
              createdAt: now,
              updatedAt: now,
              wordbookId: wordbookId,
              spelling: word.spelling,
              meaningsJson: Value(jsonEncode(word.meanings)),
            ),
        ]),
      );
    }
    await refreshWordCount(wordbookId);
  }

  // ------------------------------------------------------------ 测验
  /// 保存一轮已完成的测验（会话 + 逐题作答），返回会话 id。
  Future<String> saveQuizResult({
    String? wordbookId,
    required QuizMode mode,
    required List<QuizAnswerDraft> answers,
    required int durationSec,
  }) async {
    final now = DateTime.now();
    final sessionId = newId();
    final correct = answers.where((answer) => answer.correct).length;

    await _db.transaction(() async {
      await _db.into(_db.quizSessions).insert(
            QuizSessionsCompanion.insert(
              id: sessionId,
              createdAt: now,
              updatedAt: now,
              wordbookId: Value(wordbookId),
              mode: mode.storageKey,
              total: Value(answers.length),
              correct: Value(correct),
              durationSec: Value(durationSec),
            ),
          );
      if (answers.isNotEmpty) {
        await _db.batch(
          (batch) => batch.insertAll(_db.quizAnswers, [
            for (final answer in answers)
              QuizAnswersCompanion.insert(
                id: newId(),
                createdAt: now,
                updatedAt: now,
                sessionId: sessionId,
                wordId: answer.wordId,
                answer: answer.answer,
                correct: Value(answer.correct),
                answeredAt: answer.answeredAt,
              ),
          ]),
        );
      }
    });

    return sessionId;
  }

  Stream<List<QuizSessionEntry>> watchRecentQuizSessions({int limit = 5}) {
    final query = _db.select(_db.quizSessions)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return query.watch().map(
          (rows) => [for (final row in rows) _toQuizSession(row)],
        );
  }

  Stream<List<QuizSessionEntry>> watchQuizSessions(
    DateTime from,
    DateTime to,
  ) {
    final query = _db.select(_db.quizSessions)
      ..where(
        (t) => t.deletedAt.isNull() &
            t.createdAt.isBiggerOrEqualValue(startOfDay(from)) &
            t.createdAt.isSmallerOrEqualValue(endOfDay(to)),
      )
      ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]);
    return query.watch().map(
          (rows) => [for (final row in rows) _toQuizSession(row)],
        );
  }

  Future<List<QuizSessionEntry>> quizSessionsOnce(
    DateTime from,
    DateTime to,
  ) async {
    final rows = await (_db.select(_db.quizSessions)
          ..where(
            (t) => t.deletedAt.isNull() &
                t.createdAt.isBiggerOrEqualValue(startOfDay(from)) &
                t.createdAt.isSmallerOrEqualValue(endOfDay(to)),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
    return [for (final row in rows) _toQuizSession(row)];
  }

  QuizSessionEntry _toQuizSession(QuizSession row) => QuizSessionEntry(
        id: row.id,
        wordbookId: row.wordbookId,
        mode: QuizModeLabel.fromStorage(row.mode),
        total: row.total,
        correct: row.correct,
        durationSec: row.durationSec,
        createdAt: row.createdAt,
      );

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
