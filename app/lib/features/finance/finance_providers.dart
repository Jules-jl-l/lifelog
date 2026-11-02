/// 财务模块的 Riverpod Provider。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/finance_assets.dart';
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

/// 资产计算所需的流水（含转账转入账户）。
final assetFlowsProvider = StreamProvider<List<AssetFlow>>(
  (ref) => ref.watch(financeRepositoryProvider).watchAssetFlows(),
);

final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(financeRepositoryProvider).watchCategories(),
);

/// 商户 / 备注历史回溯的查询键。
typedef SuggestionKey = ({TxnKind kind, String categoryId});

/// 选中分类后，该分类下出现最多的商户。
final payeeSuggestionsProvider =
    StreamProvider.family<List<String>, SuggestionKey>((ref, key) {
  return ref.watch(financeRepositoryProvider).watchFrequentValues(
        kind: key.kind,
        categoryId: key.categoryId,
        payee: true,
      );
});

/// 选中分类后，该分类下出现最多的备注。
final noteSuggestionsProvider =
    StreamProvider.family<List<String>, SuggestionKey>((ref, key) {
  return ref.watch(financeRepositoryProvider).watchFrequentValues(
        kind: key.kind,
        categoryId: key.categoryId,
        payee: false,
      );
});

final budgetsProvider = StreamProvider.family<List<Budget>, String>(
  (ref, period) =>
      ref.watch(financeRepositoryProvider).watchBudgets(period),
);
