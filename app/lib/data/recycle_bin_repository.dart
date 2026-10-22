/// 回收站：列出软删除的数据，支持恢复、彻底删除与清空。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import 'db/database.dart';

enum RecycleKind {
  transaction,
  account,
  category,
  budget,
  weight,
  measure,
  workout,
  word,
  wordbook,
}

extension RecycleKindLabel on RecycleKind {
  String get label => switch (this) {
        RecycleKind.transaction => '流水',
        RecycleKind.account => '账户',
        RecycleKind.category => '分类',
        RecycleKind.budget => '预算',
        RecycleKind.weight => '体重',
        RecycleKind.measure => '围度',
        RecycleKind.workout => '运动',
        RecycleKind.word => '单词',
        RecycleKind.wordbook => '词库',
      };
}

class RecycleItem {
  const RecycleItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.deletedAt,
  });

  final RecycleKind kind;
  final String id;
  final String title;
  final String subtitle;
  final DateTime deletedAt;
}

class RecycleBinRepository {
  RecycleBinRepository(this._db);

  final AppDatabase _db;

  /// 列出全部软删除记录，按删除时间倒序。
  Future<List<RecycleItem>> list() async {
    final items = <RecycleItem>[];

    final accounts = await _db.select(_db.accounts).get();
    final accountNames = {for (final row in accounts) row.id: row.name};
    final categories = await _db.select(_db.categories).get();
    final categoryNames = {for (final row in categories) row.id: row.name};
    final wordbooks = await _db.select(_db.wordbooks).get();
    final deletedWordbookIds = {
      for (final row in wordbooks)
        if (row.deletedAt != null) row.id,
    };

    for (final row in accounts.where((row) => row.deletedAt != null)) {
      items.add(
        RecycleItem(
          kind: RecycleKind.account,
          id: row.id,
          title: row.name,
          subtitle: '${row.type.label} · 初始余额 ¥${_yuan(row.balanceInit)}',
          deletedAt: row.deletedAt!,
        ),
      );
    }

    for (final row in categories.where((row) => row.deletedAt != null)) {
      items.add(
        RecycleItem(
          kind: RecycleKind.category,
          id: row.id,
          title: row.name,
          subtitle: row.kind.label,
          deletedAt: row.deletedAt!,
        ),
      );
    }

    final transactions =
        await (_db.select(_db.transactions)..where((t) => t.deletedAt.isNotNull()))
            .get();
    for (final row in transactions) {
      final detail = [
        if (row.payee != null && row.payee!.isNotEmpty) row.payee!,
        if (row.note != null && row.note!.isNotEmpty) row.note!,
      ].join(' · ');
      items.add(
        RecycleItem(
          kind: RecycleKind.transaction,
          id: row.id,
          title:
              '${row.kind.label} ¥${_yuan(row.amount)}${detail.isEmpty ? '' : ' · $detail'}',
          subtitle: [
            if (categoryNames[row.categoryId] != null)
              categoryNames[row.categoryId]!,
            if (accountNames[row.accountId] != null)
              accountNames[row.accountId]!,
          ].join(' · '),
          deletedAt: row.deletedAt!,
        ),
      );
    }

    final budgets =
        await (_db.select(_db.budgets)..where((t) => t.deletedAt.isNotNull()))
            .get();
    for (final row in budgets) {
      items.add(
        RecycleItem(
          kind: RecycleKind.budget,
          id: row.id,
          title: '${row.period} 预算 ¥${_yuan(row.amount)}',
          subtitle: row.categoryId == null
              ? '总预算'
              : categoryNames[row.categoryId] ?? '分类预算',
          deletedAt: row.deletedAt!,
        ),
      );
    }

    final weights = await (_db.select(_db.weightRecords)
          ..where((t) => t.deletedAt.isNotNull()))
        .get();
    for (final row in weights) {
      items.add(
        RecycleItem(
          kind: RecycleKind.weight,
          id: row.id,
          title: '体重 ${(row.weightGrams / 1000).toStringAsFixed(2)} kg',
          subtitle: row.note?.trim().isNotEmpty == true ? row.note! : '体重记录',
          deletedAt: row.deletedAt!,
        ),
      );
    }

    final measures = await (_db.select(_db.bodyMeasures)
          ..where((t) => t.deletedAt.isNotNull()))
        .get();
    for (final row in measures) {
      items.add(
        RecycleItem(
          kind: RecycleKind.measure,
          id: row.id,
          title: '${row.part} ${(row.valueMm / 10).toStringAsFixed(1)} cm',
          subtitle: row.note?.trim().isNotEmpty == true ? row.note! : '围度记录',
          deletedAt: row.deletedAt!,
        ),
      );
    }

    final workouts =
        await (_db.select(_db.workouts)..where((t) => t.deletedAt.isNotNull()))
            .get();
    for (final row in workouts) {
      items.add(
        RecycleItem(
          kind: RecycleKind.workout,
          id: row.id,
          title: '${row.type} ${row.durationMin} 分钟',
          subtitle: row.note?.trim().isNotEmpty == true ? row.note! : '运动记录',
          deletedAt: row.deletedAt!,
        ),
      );
    }

    final words =
        await (_db.select(_db.words)..where((t) => t.deletedAt.isNotNull()))
            .get();
    for (final row in words.where(
      (row) => !deletedWordbookIds.contains(row.wordbookId),
    )) {
      items.add(
        RecycleItem(
          kind: RecycleKind.word,
          id: row.id,
          title: row.spelling,
          subtitle: _firstMeaning(row.meaningsJson) ?? '单词',
          deletedAt: row.deletedAt!,
        ),
      );
    }

    for (final row in wordbooks.where((row) => row.deletedAt != null)) {
      items.add(
        RecycleItem(
          kind: RecycleKind.wordbook,
          id: row.id,
          title: row.name,
          subtitle: '${row.wordCount} 词 · ${row.source == 'builtin' ? '内置' : '自建'}',
          deletedAt: row.deletedAt!,
        ),
      );
    }

    items.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return items;
  }

  Future<void> restore(RecycleItem item) async {
    final now = DateTime.now();
    switch (item.kind) {
      case RecycleKind.transaction:
        await (_db.update(_db.transactions)..where((t) => t.id.equals(item.id)))
            .write(
          TransactionsCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
      case RecycleKind.account:
        await (_db.update(_db.accounts)..where((t) => t.id.equals(item.id)))
            .write(
          AccountsCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
      case RecycleKind.category:
        await (_db.update(_db.categories)..where((t) => t.id.equals(item.id)))
            .write(
          CategoriesCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
      case RecycleKind.budget:
        await (_db.update(_db.budgets)..where((t) => t.id.equals(item.id)))
            .write(
          BudgetsCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
      case RecycleKind.weight:
        await (_db.update(_db.weightRecords)..where((t) => t.id.equals(item.id)))
            .write(
          WeightRecordsCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
      case RecycleKind.measure:
        await (_db.update(_db.bodyMeasures)..where((t) => t.id.equals(item.id)))
            .write(
          BodyMeasuresCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
      case RecycleKind.workout:
        await (_db.update(_db.workouts)..where((t) => t.id.equals(item.id)))
            .write(
          WorkoutsCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
      case RecycleKind.word:
        await (_db.update(_db.words)..where((t) => t.id.equals(item.id))).write(
          WordsCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
      case RecycleKind.wordbook:
        final book = await (_db.select(_db.wordbooks)
              ..where((t) => t.id.equals(item.id)))
            .getSingleOrNull();
        if (book != null) {
          final cutoff = book.deletedAt;
          await (_db.update(_db.words)
                ..where(
                  (t) => t.wordbookId.equals(item.id) &
                      (cutoff == null
                          ? t.deletedAt.isNotNull()
                          : t.deletedAt.equals(cutoff)),
                ))
              .write(
            WordsCompanion(
              deletedAt: const Value(null),
              updatedAt: Value(now),
            ),
          );
        }
        await (_db.update(_db.wordbooks)..where((t) => t.id.equals(item.id)))
            .write(
          WordbooksCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
    }
  }

  Future<void> deleteForever(RecycleItem item) async {
    switch (item.kind) {
      case RecycleKind.transaction:
        await (_db.delete(_db.transactions)..where((t) => t.id.equals(item.id)))
            .go();
      case RecycleKind.account:
        await (_db.delete(_db.accounts)..where((t) => t.id.equals(item.id)))
            .go();
      case RecycleKind.category:
        await (_db.delete(_db.categories)..where((t) => t.id.equals(item.id)))
            .go();
      case RecycleKind.budget:
        await (_db.delete(_db.budgets)..where((t) => t.id.equals(item.id)))
            .go();
      case RecycleKind.weight:
        await (_db.delete(_db.weightRecords)..where((t) => t.id.equals(item.id)))
            .go();
      case RecycleKind.measure:
        await (_db.delete(_db.bodyMeasures)..where((t) => t.id.equals(item.id)))
            .go();
      case RecycleKind.workout:
        await (_db.delete(_db.workouts)..where((t) => t.id.equals(item.id)))
            .go();
      case RecycleKind.word:
        await (_db.delete(_db.reviewRecords)
              ..where((t) => t.wordId.equals(item.id)))
            .go();
        await (_db.delete(_db.quizAnswers)
              ..where((t) => t.wordId.equals(item.id)))
            .go();
        await (_db.delete(_db.words)..where((t) => t.id.equals(item.id))).go();
      case RecycleKind.wordbook:
        final words = await (_db.select(_db.words)
              ..where((t) => t.wordbookId.equals(item.id)))
            .get();
        final ids = [for (final word in words) word.id];
        if (ids.isNotEmpty) {
          await (_db.delete(_db.reviewRecords)
                ..where((t) => t.wordId.isIn(ids)))
              .go();
          await (_db.delete(_db.quizAnswers)
                ..where((t) => t.wordId.isIn(ids)))
              .go();
          await (_db.delete(_db.words)
                ..where((t) => t.wordbookId.equals(item.id)))
              .go();
        }
        await (_db.delete(_db.wordbooks)..where((t) => t.id.equals(item.id)))
            .go();
    }
  }

  /// 彻底删除全部回收站内容，返回删除条数。
  Future<int> clearAll() async {
    final items = await list();
    // 先处理单词，再处理词库，避免级联删除后重复处理。
    items.sort((a, b) {
      if (a.kind == RecycleKind.word && b.kind != RecycleKind.word) return -1;
      if (b.kind == RecycleKind.word && a.kind != RecycleKind.word) return 1;
      return a.deletedAt.compareTo(b.deletedAt);
    });
    await _db.transaction(() async {
      for (final item in items) {
        await deleteForever(item);
      }
    });
    return items.length;
  }

  String _yuan(int cents) => (cents / 100).toStringAsFixed(2);

  String? _firstMeaning(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is List && decoded.isNotEmpty) return decoded.first.toString();
    } on FormatException {
      return null;
    }
    return null;
  }
}
