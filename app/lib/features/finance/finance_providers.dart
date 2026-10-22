/// 财务模块的 Riverpod Provider。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/finance_stats.dart';
import '../../data/providers.dart';

/// 查询区间（用记录类型做 family key，天然具备值相等语义）。
typedef DateRangeKey = ({DateTime start, DateTime end});

/// 区间内的流水，用于统计。
final entriesProvider =
    StreamProvider.family<List<TxnEntry>, DateRangeKey>((ref, key) {
  return ref
      .watch(financeRepositoryProvider)
      .watchEntries(key.start, key.end);
});

final accountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(financeRepositoryProvider).watchAccounts(),
);

/// 账户流水净额（收入 - 支出），资产管家用。
final accountDeltasProvider = StreamProvider<Map<String, int>>(
  (ref) => ref.watch(financeRepositoryProvider).watchAccountDeltas(),
);

final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(financeRepositoryProvider).watchCategories(),
);

final budgetsProvider = StreamProvider.family<List<Budget>, String>(
  (ref, period) =>
      ref.watch(financeRepositoryProvider).watchBudgets(period),
);
