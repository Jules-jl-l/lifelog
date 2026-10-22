/// Drift 数据库：本地 SQLite 唯一存储。
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

// 便于使用方一次性拿到表定义与枚举（TxnKind / AccountType / TxnSource）
export 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  Accounts,
  Categories,
  Transactions,
  Budgets,
  AssetSnapshots,
  WeightRecords,
  BodyMeasures,
  Workouts,
  Wordbooks,
  Words,
  ReviewRecords,
  StudyStats,
  QuizSessions,
  QuizAnswers,
  ChatSessions,
  ChatMessages,
  AiToolCalls,
  AiPendingTasks,
  AppSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 测试用：注入内存数据库。
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v1 -> v2：离线队列补一个失败原因字段
          if (from < 2) {
            await m.addColumn(aiPendingTasks, aiPendingTasks.lastError);
          }
          // v2 -> v3：账户补银行卡号前四位 / 后四位
          if (from < 3) {
            await m.addColumn(accounts, accounts.cardFirst4);
            await m.addColumn(accounts, accounts.cardLast4);
          }
          // v3 -> v4：新增拼写 / 听写测验
          if (from < 4) {
            await m.createTable(quizSessions);
            await m.createTable(quizAnswers);
          }
          // v4 -> v5：账户分资产/投资/负债三类，转账补充转入账户
          if (from < 5) {
            await m.addColumn(accounts, accounts.customLabel);
            await m.addColumn(accounts, accounts.marketAdjustment);
            await m.addColumn(transactions, transactions.toAccountId);
            // 老版本转账只记了「转入：账户名」，尽力回填转入账户。
            await customStatement(
              "UPDATE transactions SET to_account_id = ("
              "SELECT id FROM accounts "
              "WHERE accounts.name = substr(transactions.note, 4) "
              "AND accounts.deleted_at IS NULL LIMIT 1"
              ") WHERE kind = 'transfer' "
              "AND to_account_id IS NULL "
              "AND note LIKE '转入：%'",
            );
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

LazyDatabase _openConnection() => LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'lifelog.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
