/// 备份服务：抓取本地库全量快照、加密导出、解密恢复。
///
/// 采用「逐表原始值导出」而不是整文件拷贝：这样恢复可以在应用运行时完成，
/// 不需要关闭数据库或重启 App，也不依赖 SQLite 文件路径。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show TableUpdate;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'backup_codec.dart';
import '../db/database.dart';

/// 恢复结果。
class BackupImportReport {
  const BackupImportReport({required this.tables, required this.rows});

  final int tables;
  final int rows;
}

class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  static final _columnPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// 抓取全库快照（逐表 `SELECT *`，保留原始存储值）。
  Future<BackupPayload> snapshot() async {
    final tables = <String, List<Map<String, dynamic>>>{};
    final counts = <String, int>{};

    for (final table in _db.allTables) {
      final name = table.actualTableName;
      final rows = await _db.customSelect('SELECT * FROM $name').get();
      tables[name] = [for (final row in rows) row.data];
      counts[name] = rows.length;
    }

    return BackupPayload(
      info: BackupInfo(
        exportedAt: DateTime.now(),
        schemaVersion: _db.schemaVersion,
        formatVersion: backupFormatVersion,
        tableCounts: counts,
      ),
      tables: tables,
    );
  }

  /// 导出加密备份包。
  Future<Uint8List> exportEncrypted(String password) async {
    final payload = await snapshot();
    return encodeBackup(payload: payload, password: password);
  }

  /// 把备份包写入应用文档目录，返回文件句柄。
  Future<File> writeToFile(Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'lifelog-${_fileStamp(DateTime.now())}.lifelog'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// 恢复备份。
  ///
  /// [replace] 为 true 时先清空再写入（覆盖恢复）；为 false 时按主键合并。
  /// 整个过程在单个事务里完成，中途失败会整体回滚，不会留下半份数据。
  Future<BackupImportReport> restore(
    BackupPayload payload, {
    bool replace = true,
  }) async {
    final known = {
      for (final table in _db.allTables) table.actualTableName,
    };

    var tableCount = 0;
    var rowCount = 0;

    await _db.transaction(() async {
      if (replace) {
        for (final table in _db.allTables) {
          final name = table.actualTableName;
          if (!payload.tables.containsKey(name)) continue;
          await _db.customStatement('DELETE FROM $name');
        }
      }

      final verb = replace ? 'INSERT' : 'INSERT OR REPLACE';

      for (final entry in payload.tables.entries) {
        // 只接受本 App 认识的表名，避免备份文件携带任意 SQL
        if (!known.contains(entry.key)) continue;

        final rows = entry.value;
        if (rows.isEmpty) continue;
        tableCount++;

        for (final row in rows) {
          final columns = [
            for (final column in row.keys)
              if (_columnPattern.hasMatch(column)) column,
          ];
          if (columns.isEmpty) continue;

          final quoted = columns.map((name) => '"$name"').join(', ');
          final placeholders =
              List.filled(columns.length, '?').join(', ');
          await _db.customStatement(
            '$verb INTO ${entry.key} ($quoted) VALUES ($placeholders)',
            [for (final column in columns) row[column]],
          );
          rowCount++;
        }
      }
    });

    // customStatement 不经过 Drift 的查询引擎，需要手动通知一次，页面上的流才会刷新
    _db.notifyUpdates({
      for (final table in _db.allTables) TableUpdate.onTable(table),
    });

    return BackupImportReport(tables: tableCount, rows: rowCount);
  }
}

String _fileStamp(DateTime value) {
  String pad(int input) => input.toString().padLeft(2, '0');
  return '${value.year}${pad(value.month)}${pad(value.day)}'
      '-${pad(value.hour)}${pad(value.minute)}${pad(value.second)}';
}
