/// 学习模块的 Riverpod Provider。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_x.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import '../../data/study_stats.dart';

final wordbooksProvider = StreamProvider<List<Wordbook>>(
  (ref) => ref.watch(studyRepositoryProvider).watchWordbooks(),
);

final wordsProvider = StreamProvider.family<List<WordEntry>, String?>(
  (ref, wordbookId) =>
      ref.watch(studyRepositoryProvider).watchWords(wordbookId: wordbookId),
);

final reviewsProvider = StreamProvider<List<ReviewEntry>>(
  (ref) => ref.watch(studyRepositoryProvider).watchReviews(),
);

final studyStatsProvider =
    StreamProvider.family<List<StudyStatEntry>, ({DateTime start, DateTime end})>(
  (ref, range) =>
      ref.watch(studyRepositoryProvider).watchStats(range.start, range.end),
);

/// 全部卡片状态：词条 + 每个词最新的一条复习记录。
final cardStatesProvider = Provider<List<CardState>>((ref) {
  final words = ref.watch(wordsProvider(null)).dataOrNull ?? const <WordEntry>[];
  final reviews =
      ref.watch(reviewsProvider).dataOrNull ?? const <ReviewEntry>[];
  return buildCardStates(words, latestByWord(reviews));
});

/// 今日队列（到期复习优先，再补新词）。
final dailyQueueProvider = Provider<List<CardState>>((ref) {
  return buildDailyQueue(
    cards: ref.watch(cardStatesProvider),
    now: DateTime.now(),
  );
});
