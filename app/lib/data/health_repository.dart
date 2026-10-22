/// 健康模块数据访问层：体重、围度、运动三类记录的读写。
library;

import 'package:drift/drift.dart';

import '../core/utils.dart';
import 'db/database.dart';
import 'health_stats.dart';

class HealthRepository {
  HealthRepository(this._db);

  final AppDatabase _db;

  // ------------------------------------------------------------ 体重
  Stream<List<WeightEntry>> watchWeightEntries(DateTime from, DateTime to) {
    final query = _db.select(_db.weightRecords)
      ..where(
        (t) => t.deletedAt.isNull() &
            t.recordedAt.isBiggerOrEqualValue(startOfDay(from)) &
            t.recordedAt.isSmallerOrEqualValue(endOfDay(to)),
      )
      ..orderBy([(t) => OrderingTerm(expression: t.recordedAt)]);
    return query.watch().map(
          (rows) => [
            for (final row in rows)
              WeightEntry(id: row.id, at: row.recordedAt, grams: row.weightGrams),
          ],
        );
  }

  /// 最近一次体重（不受区间限制，用于展示「当前体重」）。
  Stream<WeightEntry?> watchLatestWeight() {
    final query = _db.select(_db.weightRecords)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.recordedAt, mode: OrderingMode.desc),
      ])
      ..limit(1);
    return query.watchSingleOrNull().map(
          (row) => row == null
              ? null
              : WeightEntry(
                  id: row.id,
                  at: row.recordedAt,
                  grams: row.weightGrams,
                ),
        );
  }

  Future<void> saveWeight({
    String? id,
    required DateTime recordedAt,
    required int grams,
    double? bodyFatPct,
    String? note,
  }) async {
    final now = DateTime.now();
    if (id == null) {
      await _db.into(_db.weightRecords).insert(
            WeightRecordsCompanion.insert(
              id: newId(),
              createdAt: now,
              updatedAt: now,
              recordedAt: recordedAt,
              weightGrams: grams,
              bodyFatPct: Value(bodyFatPct),
              note: Value(note),
            ),
          );
      return;
    }
    await (_db.update(_db.weightRecords)..where((t) => t.id.equals(id))).write(
      WeightRecordsCompanion(
        recordedAt: Value(recordedAt),
        weightGrams: Value(grams),
        bodyFatPct: Value(bodyFatPct),
        note: Value(note),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> deleteWeight(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.weightRecords)..where((t) => t.id.equals(id))).write(
      WeightRecordsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  // ------------------------------------------------------------ 围度
  Stream<List<MeasureEntry>> watchMeasureEntries(DateTime from, DateTime to) {
    final query = _db.select(_db.bodyMeasures)
      ..where(
        (t) => t.deletedAt.isNull() &
            t.measuredAt.isBiggerOrEqualValue(startOfDay(from)) &
            t.measuredAt.isSmallerOrEqualValue(endOfDay(to)),
      )
      ..orderBy([(t) => OrderingTerm(expression: t.measuredAt)]);
    return query.watch().map(
          (rows) => [
            for (final row in rows)
              MeasureEntry(
                id: row.id,
                at: row.measuredAt,
                part: row.part,
                mm: row.valueMm,
              ),
          ],
        );
  }

  Future<void> saveMeasure({
    String? id,
    required DateTime measuredAt,
    required String part,
    required int mm,
    String? note,
  }) async {
    final now = DateTime.now();
    if (id == null) {
      await _db.into(_db.bodyMeasures).insert(
            BodyMeasuresCompanion.insert(
              id: newId(),
              createdAt: now,
              updatedAt: now,
              measuredAt: measuredAt,
              part: part,
              valueMm: mm,
              note: Value(note),
            ),
          );
      return;
    }
    await (_db.update(_db.bodyMeasures)..where((t) => t.id.equals(id))).write(
      BodyMeasuresCompanion(
        measuredAt: Value(measuredAt),
        part: Value(part),
        valueMm: Value(mm),
        note: Value(note),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> deleteMeasure(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.bodyMeasures)..where((t) => t.id.equals(id))).write(
      BodyMeasuresCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  // ------------------------------------------------------------ 运动
  Stream<List<WorkoutEntry>> watchWorkoutEntries(DateTime from, DateTime to) {
    final query = _db.select(_db.workouts)
      ..where(
        (t) => t.deletedAt.isNull() &
            t.startedAt.isBiggerOrEqualValue(startOfDay(from)) &
            t.startedAt.isSmallerOrEqualValue(endOfDay(to)),
      )
      ..orderBy([(t) => OrderingTerm(expression: t.startedAt)]);
    return query.watch().map(
          (rows) => [
            for (final row in rows)
              WorkoutEntry(
                id: row.id,
                at: row.startedAt,
                minutes: row.durationMin,
                type: row.type,
                meters: row.distanceM,
                calories: row.calories,
                avgHr: row.avgHr,
              ),
          ],
        );
  }

  Future<void> saveWorkout({
    String? id,
    required DateTime startedAt,
    required int minutes,
    required String type,
    int? meters,
    int? calories,
    int? avgHr,
    String? note,
  }) async {
    final now = DateTime.now();
    if (id == null) {
      await _db.into(_db.workouts).insert(
            WorkoutsCompanion.insert(
              id: newId(),
              createdAt: now,
              updatedAt: now,
              startedAt: startedAt,
              durationMin: minutes,
              type: type,
              distanceM: Value(meters),
              calories: Value(calories),
              avgHr: Value(avgHr),
              note: Value(note),
            ),
          );
      return;
    }
    await (_db.update(_db.workouts)..where((t) => t.id.equals(id))).write(
      WorkoutsCompanion(
        startedAt: Value(startedAt),
        durationMin: Value(minutes),
        type: Value(type),
        distanceM: Value(meters),
        calories: Value(calories),
        avgHr: Value(avgHr),
        note: Value(note),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> deleteWorkout(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.workouts)..where((t) => t.id.equals(id))).write(
      WorkoutsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  // ------------------------------------------------------------ Future 版本（供 AI 工具使用）
  /// 最近一条体重原始记录（含体脂率，供 AI 工具读取）。
  Future<WeightRecord?> latestWeightRow() async {
    final query = _db.select(_db.weightRecords)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.recordedAt, mode: OrderingMode.desc),
      ])
      ..limit(1);
    return query.getSingleOrNull();
  }

  Future<WeightEntry?> latestWeight() async {
    final query = _db.select(_db.weightRecords)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.recordedAt, mode: OrderingMode.desc),
      ])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null
        ? null
        : WeightEntry(id: row.id, at: row.recordedAt, grams: row.weightGrams);
  }

  Future<List<WeightEntry>> weightEntriesInRange(
    DateTime from,
    DateTime to,
  ) async {
    final rows = await (_db.select(_db.weightRecords)
          ..where(
            (t) => t.deletedAt.isNull() &
                t.recordedAt.isBiggerOrEqualValue(startOfDay(from)) &
                t.recordedAt.isSmallerOrEqualValue(endOfDay(to)),
          ))
        .get();
    return [
      for (final row in rows)
        WeightEntry(id: row.id, at: row.recordedAt, grams: row.weightGrams),
    ];
  }

  Future<List<MeasureEntry>> measureEntriesInRange(
    DateTime from,
    DateTime to,
  ) async {
    final rows = await (_db.select(_db.bodyMeasures)
          ..where(
            (t) => t.deletedAt.isNull() &
                t.measuredAt.isBiggerOrEqualValue(startOfDay(from)) &
                t.measuredAt.isSmallerOrEqualValue(endOfDay(to)),
          ))
        .get();
    return [
      for (final row in rows)
        MeasureEntry(
          id: row.id,
          at: row.measuredAt,
          part: row.part,
          mm: row.valueMm,
        ),
    ];
  }

  Future<List<WorkoutEntry>> workoutEntriesInRange(
    DateTime from,
    DateTime to,
  ) async {
    final rows = await (_db.select(_db.workouts)
          ..where(
            (t) => t.deletedAt.isNull() &
                t.startedAt.isBiggerOrEqualValue(startOfDay(from)) &
                t.startedAt.isSmallerOrEqualValue(endOfDay(to)),
          ))
        .get();
    return [
      for (final row in rows)
        WorkoutEntry(
          id: row.id,
          at: row.startedAt,
          minutes: row.durationMin,
          type: row.type,
          meters: row.distanceM,
          calories: row.calories,
          avgHr: row.avgHr,
        ),
    ];
  }
}
