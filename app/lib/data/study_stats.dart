/// 学习模块的纯逻辑：SRS 排程、今日队列、学习统计。不依赖数据库，便于单元测试。
library;

import '../core/utils.dart';

/// 复习反馈：认识 / 模糊 / 不认识。
enum ReviewResult { know, vague, unknown }

extension ReviewResultLabel on ReviewResult {
  String get label => switch (this) {
        ReviewResult.know => '认识',
        ReviewResult.vague => '模糊',
        ReviewResult.unknown => '不认识',
      };

  /// 是否计入「答对」。
  bool get isCorrect => this == ReviewResult.know;
}

/// 词条（轻量结构）。
class WordEntry {
  const WordEntry({
    required this.id,
    required this.wordbookId,
    required this.spelling,
    this.phoneticUk,
    this.phoneticUs,
    this.meanings = const [],
    this.examples = const [],
    this.tags = const [],
  });

  final String id;
  final String wordbookId;
  final String spelling;
  final String? phoneticUk;
  final String? phoneticUs;
  final List<String> meanings;
  final List<String> examples;
  final List<String> tags;
}

/// 一条复习记录（最新一条即该词的当前 SRS 状态）。
class ReviewEntry {
  const ReviewEntry({
    required this.wordId,
    required this.at,
    required this.result,
    required this.intervalDays,
    required this.ease,
    required this.repetitions,
    this.nextReviewAt,
  });

  final String wordId;
  final DateTime at;
  final ReviewResult result;
  final int intervalDays;
  final double ease;
  final int repetitions;
  final DateTime? nextReviewAt;
}

/// SRS 参数默认值。
const defaultEase = 2.5;
const minEase = 1.3;
const maxEase = 2.8;

/// 单次排程的结果。
class SrsOutcome {
  const SrsOutcome({
    required this.repetitions,
    required this.ease,
    required this.intervalDays,
    required this.nextReviewAt,
  });

  final int repetitions;
  final double ease;
  final int intervalDays;
  final DateTime nextReviewAt;
}

/// 简化版 SM-2：
/// - 认识：重复次数 +1，间隔按 ease 递增（首次 1 天、第二次 3 天）
/// - 模糊：间隔按 1.2 倍微增，ease 不变
/// - 不认识：重复次数归零，ease 下调，当天继续复习
SrsOutcome scheduleReview({
  required ReviewResult result,
  required int repetitions,
  required double ease,
  required int intervalDays,
  required DateTime now,
}) {
  switch (result) {
    case ReviewResult.unknown:
      final nextEase = (ease - 0.2).clamp(minEase, maxEase);
      return SrsOutcome(
        repetitions: 0,
        ease: nextEase,
        intervalDays: 0,
        // 当天重新出现，让用户马上再过一遍
        nextReviewAt: now.add(const Duration(minutes: 10)),
      );

    case ReviewResult.vague:
      final nextInterval = intervalDays <= 0
          ? 1
          : (intervalDays * 1.2).round().clamp(1, 365);
      return SrsOutcome(
        repetitions: repetitions,
        ease: ease.clamp(minEase, maxEase),
        intervalDays: nextInterval,
        nextReviewAt: now.add(Duration(days: nextInterval)),
      );

    case ReviewResult.know:
      final nextEase = (ease + 0.1).clamp(minEase, maxEase);
      final nextReps = repetitions + 1;
      final nextInterval = switch (nextReps) {
        1 => 1,
        2 => 3,
        _ => (intervalDays <= 0 ? 3 : (intervalDays * nextEase).round())
            .clamp(1, 365),
      };
      return SrsOutcome(
        repetitions: nextReps,
        ease: nextEase,
        intervalDays: nextInterval,
        nextReviewAt: now.add(Duration(days: nextInterval)),
      );
  }
}

/// 一张卡片的当前状态。
class CardState {
  const CardState({
    required this.word,
    this.repetitions = 0,
    this.ease = defaultEase,
    this.intervalDays = 0,
    this.nextReviewAt,
  });

  final WordEntry word;
  final int repetitions;
  final double ease;
  final int intervalDays;
  final DateTime? nextReviewAt;

  /// 从未复习过的新词。
  bool get isNew => repetitions == 0 && nextReviewAt == null;

  bool isDue(DateTime now) =>
      nextReviewAt != null && !nextReviewAt!.isAfter(now);
}

/// 把词条与「每个词最新的一条复习记录」合并成卡片状态。
List<CardState> buildCardStates(
  List<WordEntry> words,
  Map<String, ReviewEntry> latestReviews,
) {
  return [
    for (final word in words)
      if (latestReviews[word.id] case final review?)
        CardState(
          word: word,
          repetitions: review.repetitions,
          ease: review.ease,
          intervalDays: review.intervalDays,
          nextReviewAt: review.nextReviewAt,
        )
      else
        CardState(word: word),
  ];
}

/// 今日队列：先排到期复习（按到期时间先后），再补足新词上限。
List<CardState> buildDailyQueue({
  required List<CardState> cards,
  required DateTime now,
  int newLimit = 20,
}) {
  final due = cards.where((card) => card.isDue(now)).toList()
    ..sort((a, b) => a.nextReviewAt!.compareTo(b.nextReviewAt!));

  final fresh = cards.where((card) => card.isNew).toList()
    ..sort((a, b) => a.word.spelling.compareTo(b.word.spelling));

  return [...due, ...fresh.take(newLimit)];
}

/// 把「每个词的最新复习记录」从全部记录里挑出来（按时间取最新）。
///
/// 同一毫秒内的多条记录无法靠时间区分，这里按「后出现的覆盖先出现的」处理，
/// 依赖调用方传入的记录本身是按写入顺序排列的。
Map<String, ReviewEntry> latestByWord(Iterable<ReviewEntry> reviews) {
  final result = <String, ReviewEntry>{};
  for (final review in reviews) {
    final current = result[review.wordId];
    if (current == null || !review.at.isBefore(current.at)) {
      result[review.wordId] = review;
    }
  }
  return result;
}

// ---------------------------------------------------------------- 统计

/// 某一天的汇总（对应 study_stats 一行）。
class StudyStatEntry {
  const StudyStatEntry({
    required this.statDate,
    this.newCount = 0,
    this.reviewCount = 0,
    this.correctRate = 0,
    this.durationSec = 0,
  });

  /// YYYY-MM-DD
  final String statDate;
  final int newCount;
  final int reviewCount;
  final double correctRate;
  final int durationSec;

  int get total => newCount + reviewCount;
}

class StudySummary {
  const StudySummary({
    this.newCount = 0,
    this.reviewCount = 0,
    this.correctCount = 0,
    this.durationSec = 0,
  });

  final int newCount;
  final int reviewCount;
  final int correctCount;
  final int durationSec;

  int get total => newCount + reviewCount;

  double get correctRate => total == 0 ? 0 : correctCount / total;
}

/// 按「答题量」加权汇总：天级只存了正确率，跨天聚合用总量做权重。
StudySummary summarizeStudy(Iterable<StudyStatEntry> entries) {
  var newCount = 0;
  var reviewCount = 0;
  var durationSec = 0;
  var weightedCorrect = 0.0;

  for (final entry in entries) {
    newCount += entry.newCount;
    reviewCount += entry.reviewCount;
    durationSec += entry.durationSec;
    weightedCorrect += entry.correctRate * entry.total;
  }

  return StudySummary(
    newCount: newCount,
    reviewCount: reviewCount,
    correctCount: weightedCorrect.round(),
    durationSec: durationSec,
  );
}

/// 学习量趋势（每天已学词数），空档补 null。
List<MetricPoint> studyTrend(
  Iterable<StudyStatEntry> entries,
  StatsPeriod period,
  DateTime anchor,
) {
  final totals = <String, int>{};
  for (final entry in entries) {
    final parsed = DateTime.tryParse(entry.statDate);
    if (parsed == null) continue;
    final key = bucketKeyOf(parsed, period);
    totals[key] = (totals[key] ?? 0) + entry.total;
  }

  return [
    for (final key in bucketKeys(period, anchor))
      MetricPoint(bucket: key, value: totals[key]?.toDouble()),
  ];
}

/// 秒 -> 「12 分 30 秒」。
String formatStudyDuration(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return rest == 0 ? '$minutes 分钟' : '$minutes 分 $rest 秒';
}
