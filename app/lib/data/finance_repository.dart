/// 财务模块数据访问层：把 Drift 查询收敛在这里，页面只依赖本类。
library;

import 'package:drift/drift.dart';

import '../core/utils.dart';
import 'db/database.dart';
import 'finance_assets.dart';
import 'finance_stats.dart';

class FinanceRepository {
  FinanceRepository(this._db);

  final AppDatabase _db;

  // ------------------------------------------------------------ 账户
  Stream<List<Account>> watchAccounts() {
    final query = _db.select(_db.accounts)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.sort)]);
    return query.watch();
  }

  /// 每个账户的流水净额（收入 - 支出），资产管家用于计算实时余额。
  Stream<Map<String, int>> watchAccountDeltas() {
    final query = _db.select(_db.transactions)
      ..where((t) => t.deletedAt.isNull() & t.accountId.isNotNull());
    return query.watch().map((rows) {
      final deltas = <String, int>{};
      for (final row in rows) {
        final id = row.accountId!;
        final delta = switch (row.kind) {
          TxnKind.income => row.amount,
          TxnKind.expense => -row.amount,
          TxnKind.transfer => 0,
        };
        deltas[id] = (deltas[id] ?? 0) + delta;
      }
      return deltas;
    });
  }

  /// 保存账户，返回账户 id（新建时生成，编辑时原样返回）。
  Future<String> saveAccount({
    String? id,
    required String name,
    required AccountType type,
    int balanceInit = 0,
    String? customType,
    int marketAdjustment = 0,
    String? cardFirst4,
    String? cardLast4,
    int sort = 0,
  }) async {
    final now = DateTime.now();
    final accountId = id ?? newId();
    if (id == null) {
      await _db.into(_db.accounts).insert(
            AccountsCompanion.insert(
              id: accountId,
              createdAt: now,
              updatedAt: now,
              name: name,
              type: type,
              balanceInit: Value(balanceInit),
              customLabel: Value(customType),
              marketAdjustment: Value(marketAdjustment),
              cardFirst4: Value(cardFirst4),
              cardLast4: Value(cardLast4),
              sort: Value(sort),
            ),
          );
      return accountId;
    }
    await (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(
        name: Value(name),
        type: Value(type),
        balanceInit: Value(balanceInit),
        customLabel: Value(customType),
        marketAdjustment: Value(marketAdjustment),
        cardFirst4: Value(cardFirst4),
        cardLast4: Value(cardLast4),
        sort: Value(sort),
        updatedAt: Value(now),
      ),
    );
    return accountId;
  }

  Future<void> deleteAccount(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  /// 未删除账户的一次性读取（供 AI 工具使用）。
  Future<List<Account>> accountsOnce() async {
    final query = _db.select(_db.accounts)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.sort)]);
    return query.get();
  }

  /// 每个账户的流水净额（收入 - 支出），一次性版本。
  Future<Map<String, int>> accountDeltasOnce() async {
    final rows = await (_db.select(_db.transactions)
          ..where((t) => t.deletedAt.isNull() & t.accountId.isNotNull()))
        .get();
    final deltas = <String, int>{};
    for (final row in rows) {
      final id = row.accountId!;
      final delta = switch (row.kind) {
        TxnKind.income => row.amount,
        TxnKind.expense => -row.amount,
        TxnKind.transfer => 0,
      };
      deltas[id] = (deltas[id] ?? 0) + delta;
    }
    return deltas;
  }

  // ------------------------------------------------------------ 资产汇总
  /// 资产计算所需的流水（含转账的转入账户）。
  Stream<List<AssetFlow>> watchAssetFlows() {
    final query = _db.select(_db.transactions)
      ..where((t) => t.deletedAt.isNull());
    return query.watch().map(
          (rows) => [
            for (final row in rows)
              AssetFlow(
                kind: row.kind,
                amount: row.amount,
                accountId: row.accountId,
                toAccountId: row.toAccountId,
              ),
          ],
        );
  }

  Future<List<AssetFlow>> assetFlowsOnce() async {
    final rows = await (_db.select(_db.transactions)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    return [
      for (final row in rows)
        AssetFlow(
          kind: row.kind,
          amount: row.amount,
          accountId: row.accountId,
          toAccountId: row.toAccountId,
        ),
    ];
  }

  /// 三类资产汇总（净资产、总资产、总负债、投资盈亏）。
  Future<AssetSummary> assetSummaryOnce() async {
    final accounts = await accountsOnce();
    final flows = await assetFlowsOnce();
    return summarizeAssets(
      [for (final row in accounts) _toAssetAccount(row)],
      flows,
    );
  }

  /// 某个投资账户的累计投入本金（用于手动更新市值时算盈亏）。
  Future<int> investmentPrincipalOnce(String accountId) async {
    final summary = await assetSummaryOnce();
    return summary.accounts[accountId]?.principal ?? 0;
  }

  AssetAccount _toAssetAccount(Account row) => AssetAccount(
        id: row.id,
        type: row.type,
        balanceInit: row.balanceInit,
        marketAdjustment: row.marketAdjustment,
      );

  // ------------------------------------------------------------ 分类
  Stream<List<Category>> watchCategories({TxnKind? kind}) {
    final query = _db.select(_db.categories)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.sort)]);
    if (kind != null) {
      query.where((t) => t.kind.equalsValue(kind));
    }
    return query.watch();
  }

  /// 保存分类，返回分类 id（新建时生成，编辑时原样返回）。
  Future<String> saveCategory({
    String? id,
    required String name,
    required TxnKind kind,
    int sort = 0,
  }) async {
    final now = DateTime.now();
    final categoryId = id ?? newId();
    if (id == null) {
      await _db.into(_db.categories).insert(
            CategoriesCompanion.insert(
              id: categoryId,
              createdAt: now,
              updatedAt: now,
              name: name,
              kind: kind,
              sort: Value(sort),
            ),
          );
      return categoryId;
    }
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
      CategoriesCompanion(
        name: Value(name),
        kind: Value(kind),
        sort: Value(sort),
        updatedAt: Value(now),
      ),
    );
    return categoryId;
  }

  Future<void> deleteCategory(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
      CategoriesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  // ------------------------------------------------------------ 流水
  Stream<List<Transaction>> watchTransactions({
    TxnKind? kind,
    String? categoryId,
    DateTime? from,
    DateTime? to,
    String? keyword,
    int limit = 300,
  }) {
    final query = _db.select(_db.transactions)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);

    if (kind != null) query.where((t) => t.kind.equalsValue(kind));
    if (categoryId != null) {
      query.where((t) => t.categoryId.equals(categoryId));
    }
    if (from != null) {
      query.where((t) => t.occurredAt.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where((t) => t.occurredAt.isSmallerOrEqualValue(to));
    }
    final trimmed = keyword?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      query.where(
        (t) => t.payee.like('%$trimmed%') | t.note.like('%$trimmed%'),
      );
    }
    return query.watch();
  }

  Future<void> saveTransaction({
    String? id,
    String? accountId,
    String? toAccountId,
    String? categoryId,
    required TxnKind kind,
    required int amount,
    required DateTime occurredAt,
    String? payee,
    String? note,
    TxnSource source = TxnSource.manual,
    double? confidence,
    String? imageRef,
    String? fingerprint,
    String? tradeNo,
  }) async {
    final now = DateTime.now();
    if (id == null) {
      await _db.into(_db.transactions).insert(
            TransactionsCompanion.insert(
              id: newId(),
              createdAt: now,
              updatedAt: now,
              kind: kind,
              amount: amount,
              occurredAt: occurredAt,
              accountId: Value(accountId),
              toAccountId: Value(toAccountId),
              categoryId: Value(categoryId),
              payee: Value(payee),
              note: Value(note),
              source: Value(source),
              confidence: Value(confidence),
              imageRef: Value(imageRef),
              fingerprint: Value(fingerprint),
              tradeNo: Value(tradeNo),
            ),
          );
      return;
    }
    await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        accountId: Value(accountId),
        toAccountId: Value(toAccountId),
        categoryId: Value(categoryId),
        kind: Value(kind),
        amount: Value(amount),
        occurredAt: Value(occurredAt),
        payee: Value(payee),
        note: Value(note),
        source: Value(source),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> deleteTransaction(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  /// 按去重指纹查是否已存在，避免重复识图重复入账。
  Future<bool> existsByFingerprint(String fingerprint) async {
    final row = await (_db.select(_db.transactions)
          ..where((t) => t.fingerprint.equals(fingerprint))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  // ------------------------------------------------------------ 预算
  Stream<List<Budget>> watchBudgets(String period) {
    final query = _db.select(_db.budgets)
      ..where((t) => t.deletedAt.isNull() & t.period.equals(period));
    return query.watch();
  }

  Future<void> saveBudget({
    String? id,
    required String period,
    String? categoryId,
    required int amount,
  }) async {
    final now = DateTime.now();
    if (id == null) {
      await _db.into(_db.budgets).insert(
            BudgetsCompanion.insert(
              id: newId(),
              createdAt: now,
              updatedAt: now,
              period: period,
              amount: amount,
              categoryId: Value(categoryId),
            ),
          );
      return;
    }
    await (_db.update(_db.budgets)..where((t) => t.id.equals(id))).write(
      BudgetsCompanion(
        categoryId: Value(categoryId),
        amount: Value(amount),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> deleteBudget(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.budgets)..where((t) => t.id.equals(id))).write(
      BudgetsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  /// 某月的全部预算（含总预算与分类预算），供 AI 工具设置/查询使用。
  Future<List<Budget>> budgetsForPeriod(String period) async {
    return (_db.select(_db.budgets)
          ..where((t) => t.deletedAt.isNull() & t.period.equals(period)))
        .get();
  }

  // ------------------------------------------------------------ 统计
  /// 区间内的流水（含当天），映射成纯计算的轻量结构。
  Stream<List<TxnEntry>> watchEntries(DateTime from, DateTime to) {
    final query = _db.select(_db.transactions)
      ..where(
        (t) => t.deletedAt.isNull() &
            t.occurredAt.isBiggerOrEqualValue(startOfDay(from)) &
            t.occurredAt.isSmallerOrEqualValue(
              DateTime(to.year, to.month, to.day, 23, 59, 59, 999),
            ),
      );
    return query.watch().map(
          (rows) => [for (final row in rows) _toEntry(row)],
        );
  }

  /// 分类 id -> 名称，供页面展示使用。
  Future<Map<String, String>> categoryNameMap() async {
    final rows = await (_db.select(_db.categories)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    return {for (final row in rows) row.id: row.name};
  }

  /// 账户 id -> 名称。
  Future<Map<String, String>> accountNameMap() async {
    final rows = await (_db.select(_db.accounts)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    return {for (final row in rows) row.id: row.name};
  }

  /// 区间内的流水（含当天），供 AI 工具与离线统计使用。
  Future<List<TxnEntry>> entriesInRange(DateTime from, DateTime to) async {
    final rows = await (_db.select(_db.transactions)
          ..where(
            (t) => t.deletedAt.isNull() &
                t.occurredAt.isBiggerOrEqualValue(startOfDay(from)) &
                t.occurredAt.isSmallerOrEqualValue(endOfDay(to)),
          ))
        .get();
    return [for (final row in rows) _toEntry(row)];
  }

  /// 按名称与方向查找分类（忽略大小写），供 AI 落库时复用已有分类。
  Future<Category?> findCategoryByName(String name, TxnKind kind) async {
    final target = name.trim().toLowerCase();
    if (target.isEmpty) return null;
    final rows = await (_db.select(_db.categories)
          ..where((t) => t.deletedAt.isNull() & t.kind.equalsValue(kind)))
        .get();
    for (final row in rows) {
      if (row.name.toLowerCase() == target) return row;
    }
    return null;
  }

  /// 未删除分类的一次性读取（供 AI 工具使用）。
  Future<List<Category>> categoriesOnce({TxnKind? kind}) async {
    final query = _db.select(_db.categories)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.sort)]);
    if (kind != null) {
      query.where((t) => t.kind.equalsValue(kind));
    }
    return query.get();
  }

  TxnEntry _toEntry(Transaction row) => TxnEntry(
        id: row.id,
        kind: row.kind,
        amount: row.amount,
        occurredAt: row.occurredAt,
        categoryId: row.categoryId,
      );
}
