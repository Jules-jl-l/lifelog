/// 拼写 / 听写测验的纯逻辑：抽题、判分、汇总。不依赖数据库与 Flutter。
library;

import 'dart:math';

import '../study_stats.dart';

/// 测验模式。
enum QuizMode { meaning, dictation }

extension QuizModeLabel on QuizMode {
  String get label => switch (this) {
        QuizMode.meaning => '看释义拼写',
        QuizMode.dictation => '听音拼写',
      };

  String get description => switch (this) {
        QuizMode.meaning => '看中文释义，输入英文拼写',
        QuizMode.dictation => '听发音，输入英文拼写',
      };

  String get storageKey => name;

  static QuizMode fromStorage(String? value) {
    return QuizMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => QuizMode.meaning,
    );
  }
}

/// 一道题。
class QuizQuestion {
  const QuizQuestion({required this.word, required this.mode});

  final WordEntry word;
  final QuizMode mode;
}

/// 单轮最多题量，避免超大词库一次背太久。
const maxQuizQuestions = 50;

/// 解析用户选择的题量：<= 0 表示“全部”，并受单轮上限约束。
int resolveQuizCount({required int available, required int requested}) {
  if (available <= 0) return 0;
  final wanted = requested <= 0 ? available : requested;
  return min(wanted, min(available, maxQuizQuestions));
}

/// 抽题：打乱后取前 N 个。
///
/// 释义模式会跳过没有释义的词；听写模式只要求拼写非空。
List<QuizQuestion> pickQuizQuestions({
  required List<WordEntry> words,
  required QuizMode mode,
  required int count,
  Random? random,
}) {
  final usable = [
    for (final word in words)
      if (word.spelling.trim().isNotEmpty &&
          (mode != QuizMode.meaning ||
              word.meanings.any((meaning) => meaning.trim().isNotEmpty)))
        word,
  ];
  if (usable.isEmpty) return const [];
  final shuffled = [...usable]..shuffle(random ?? Random());
  final take = resolveQuizCount(available: shuffled.length, requested: count);
  return [
    for (final word in shuffled.take(take))
      QuizQuestion(word: word, mode: mode),
  ];
}

/// 归一化拼写：去首尾空格、合并连续空白、统一小写。
String normalizeSpelling(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// 判定拼写是否一致（忽略大小写与多余空格）。
bool isSpellingCorrect(String input, String expected) {
  final normalized = normalizeSpelling(input);
  return normalized.isNotEmpty && normalized == normalizeSpelling(expected);
}

/// 待写入的一题作答。
class QuizAnswerDraft {
  const QuizAnswerDraft({
    required this.wordId,
    required this.answer,
    required this.correct,
    required this.answeredAt,
  });

  final String wordId;
  final String answer;
  final bool correct;
  final DateTime answeredAt;
}

/// 一条测验成绩（对应 quiz_sessions 一行）。
class QuizSessionEntry {
  const QuizSessionEntry({
    required this.id,
    required this.wordbookId,
    required this.mode,
    required this.total,
    required this.correct,
    required this.durationSec,
    required this.createdAt,
  });

  final String id;
  final String? wordbookId;
  final QuizMode mode;
  final int total;
  final int correct;
  final int durationSec;
  final DateTime createdAt;

  double get accuracy => total == 0 ? 0 : correct / total;
}

class QuizSummary {
  const QuizSummary({
    this.sessions = 0,
    this.questions = 0,
    this.correct = 0,
    this.durationSec = 0,
  });

  final int sessions;
  final int questions;
  final int correct;
  final int durationSec;

  double get accuracy => questions == 0 ? 0 : correct / questions;
}

/// 汇总一段时间内的测验成绩（按题量加权）。
QuizSummary summarizeQuizSessions(Iterable<QuizSessionEntry> entries) {
  var sessions = 0;
  var questions = 0;
  var correct = 0;
  var durationSec = 0;
  for (final entry in entries) {
    sessions++;
    questions += entry.total;
    correct += entry.correct;
    durationSec += entry.durationSec;
  }
  return QuizSummary(
    sessions: sessions,
    questions: questions,
    correct: correct,
    durationSec: durationSec,
  );
}
