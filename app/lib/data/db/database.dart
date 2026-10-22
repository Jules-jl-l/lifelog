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
  int get schemaVersion => 3;

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
