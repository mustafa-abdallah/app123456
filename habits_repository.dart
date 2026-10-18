import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import '../database/database.dart';

/// المصدر الوحيد لبيانات العادات وسجلها.
class HabitsRepository {
  HabitsRepository(this._db);
  final AppDatabase _db;

  Stream<List<Habit>> watchActive() => (_db.select(_db.habits)
        ..where((h) => h.deletedAt.isNull())
        ..orderBy([(h) => OrderingTerm.asc(h.createdAt)]))
      .watch();

  /// كل السجلات من تاريخ معيّن (yyyy-MM-dd) فصاعدًا.
  Stream<List<HabitLog>> watchLogsSince(String fromDate) =>
      (_db.select(_db.habitLogs)
            ..where((l) => l.date.isBiggerOrEqualValue(fromDate)))
          .watch();

  /// أحدث جدول لكل عادة (يوم = بت). الافتراضي: كل الأيام.
  Future<Map<String, int>> masks() async {
    final rows = await (_db.select(_db.habitSchedules)
          ..where((s) => s.deletedAt.isNull() & s.validTo.isNull()))
        .get();
    return {for (final s in rows) s.habitId: s.daysMask};
  }

  Future<String> create(String name, {int daysMask = 127}) async {
    final id = const Uuid().v4();
    await _db.transaction(() async {
      await _db.into(_db.habits).insert(
          HabitsCompanion.insert(id: Value(id), name: name.trim()));
      await _db.into(_db.habitSchedules).insert(HabitSchedulesCompanion.insert(
          habitId: id, daysMask: daysMask, validFrom: formatDate(DateTime.now())));
    });
    return id;
  }

  Future<void> rename(String id, String name) =>
      (_db.update(_db.habits)..where((h) => h.id.equals(id))).write(
          HabitsCompanion(name: Value(name.trim()), updatedAt: Value(DateTime.now())));

  /// حذف منطقي؛ يبقى السجل محفوظًا.
  Future<void> softDelete(String id) =>
      (_db.update(_db.habits)..where((h) => h.id.equals(id)))
          .write(HabitsCompanion(deletedAt: Value(DateTime.now())));

  /// يسجّل اليوم كمنجز، أو يلغي التسجيل إن كان منجزًا من قبل.
  Future<void> toggleDay(String habitId, String date) async {
    final existing = await (_db.select(_db.habitLogs)
          ..where((l) => l.habitId.equals(habitId) & l.date.equals(date)))
        .getSingleOrNull();
    if (existing != null) {
      await (_db.delete(_db.habitLogs)..where((l) => l.id.equals(existing.id))).go();
    } else {
      await _db.into(_db.habitLogs).insert(HabitLogsCompanion.insert(
          habitId: habitId, date: date, value: const Value(1)));
    }
  }
}
