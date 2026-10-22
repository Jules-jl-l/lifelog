/// 健康模块的 Riverpod Provider。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/health_stats.dart';
import '../../data/providers.dart';
import '../../data/settings_repository.dart';

/// 查询区间。
typedef HealthRangeKey = ({DateTime start, DateTime end});

final weightEntriesProvider =
    StreamProvider.family<List<WeightEntry>, HealthRangeKey>(
  (ref, key) =>
      ref.watch(healthRepositoryProvider).watchWeightEntries(key.start, key.end),
);

final measureEntriesProvider =
    StreamProvider.family<List<MeasureEntry>, HealthRangeKey>(
  (ref, key) => ref
      .watch(healthRepositoryProvider)
      .watchMeasureEntries(key.start, key.end),
);

final workoutEntriesProvider =
    StreamProvider.family<List<WorkoutEntry>, HealthRangeKey>(
  (ref, key) => ref
      .watch(healthRepositoryProvider)
      .watchWorkoutEntries(key.start, key.end),
);

/// 最近一次体重（不受区间限制），用于展示「当前体重」与 BMI。
final latestWeightProvider = StreamProvider<WeightEntry?>(
  (ref) => ref.watch(healthRepositoryProvider).watchLatestWeight(),
);

/// 身高设置（厘米），用于计算 BMI。
final heightCmProvider = StreamProvider<int?>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watch(SettingKeys.heightCm)
      .map((value) => value == null ? null : int.tryParse(value)),
);
