import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import '../database/database.dart';

/// المصدر الوحيد لبيانات العادات وسجلها.
///
/// أنواع العادة [Habit.kind]: check (نعم/لا) | count (عدد) | duration (مدة).
/// حالات السجل [HabitLog.status]: done (بلغ الهدف) | partial (جزئي) | excused (إجازة).
/// الجدول التاريخي: كل تغيير في أيام العادة يُغلق الفترة الحالية ويفتح فترة جديدة،
/// فلا يتغير الماضي أبدًا. الإيقاف المؤقت = إغلاق الفترة المفتوحة دون فتح جديدة.
class HabitsRepository {
  HabitsRepository(this._db);
  final AppDatabase _db;

  Stream<List<Habit>> watchActive() => (_db.select(_db.habits)
        ..where((h) => h.deletedAt.isNull())
        ..orderBy([(h) => OrderingTerm.asc(h.createdAt)]))
      .watch();

  Future<Habit?> getById(String id) =>
      (_db.select(_db.habits)..where((h) => h.id.equals(id))).getSingleOrNull();

  /// كل السجلات من تاريخ معيّن (yyyy-MM-dd) فصاعدًا.
  Stream<List<HabitLog>> watchLogsSince(String fromDate) =>
      (_db.select(_db.habitLogs)
            ..where((l) => l.date.isBiggerOrEqualValue(fromDate)))
          .watch();

  /// كل فترات الجداول (التاريخ كاملًا).
  Stream<List<HabitSchedule>> watchSchedules() => (_db.select(_db.habitSchedules)
        ..where((s) => s.deletedAt.isNull()))
      .watch();

  /// أحدث جدول مفتوح لكل عادة (يوم = بت). الافتراضي: كل الأيام.
  Future<Map<String, int>> masks() async {
    final rows = await (_db.select(_db.habitSchedules)
          ..where((s) => s.deletedAt.isNull() & s.validTo.isNull()))
        .get();
    return {for (final s in rows) s.habitId: s.daysMask};
  }

  String _today() => formatDate(DateTime.now());
  String _yesterday() {
    final n = DateTime.now();
    return formatDate(DateTime(n.year, n.month, n.day - 1));
  }

  // ---------- الإنشاء والتعديل ----------

  Future<String> create(String name,
      {int daysMask = 127, String kind = 'check', double target = 1, String? unit}) async {
    final id = const Uuid().v4();
    await _db.transaction(() async {
      await _db.into(_db.habits).insert(HabitsCompanion.insert(
            id: Value(id),
            name: name.trim(),
            kind: Value(kind),
            targetValue: Value(kind == 'check' ? 1.0 : target),
            unit: Value(unit),
          ));
      await _db.into(_db.habitSchedules).insert(HabitSchedulesCompanion.insert(
          habitId: id, daysMask: daysMask, validFrom: _today()));
    });
    return id;
  }

  Future<void> rename(String id, String name) =>
      (_db.update(_db.habits)..where((h) => h.id.equals(id))).write(
          HabitsCompanion(name: Value(name.trim()), updatedAt: Value(DateTime.now())));

  /// يغيّر نوع الهدف وقيمته، ثم يعيد حساب حالة السجلات القديمة (تامّ/جزئي)
  /// على الهدف الجديد؛ القيم المسجّلة نفسها لا تُمسّ.
  Future<void> setGoal(String id,
      {required String kind, required double target, String? unit}) {
    return _db.transaction(() async {
      final t = kind == 'check' ? 1.0 : target;
      await (_db.update(_db.habits)..where((h) => h.id.equals(id))).write(
        HabitsCompanion(
          kind: Value(kind),
          targetValue: Value(t),
          unit: Value(kind == 'check' ? null : unit),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final logs = await (_db.select(_db.habitLogs)
            ..where((l) => l.habitId.equals(id) & l.status.isIn(['done', 'partial'])))
          .get();
      for (final l in logs) {
        final status = l.value >= t ? 'done' : 'partial';
        if (status != l.status) {
          await (_db.update(_db.habitLogs)..where((x) => x.id.equals(l.id))).write(
              HabitLogsCompanion(status: Value(status), updatedAt: Value(DateTime.now())));
        }
      }
    });
  }

  /// حذف منطقي؛ يبقى السجل محفوظًا.
  Future<void> softDelete(String id) =>
      (_db.update(_db.habits)..where((h) => h.id.equals(id)))
          .write(HabitsCompanion(deletedAt: Value(DateTime.now())));

  // ---------- الجدول والإيقاف المؤقت ----------

  /// يغيّر أيام العادة من اليوم فصاعدًا دون المساس بالماضي.
  /// لا أثر له أثناء الإيقاف المؤقت (استأنف أولًا).
  Future<void> setDays(String habitId, int mask) => _db.transaction(() async {
        final open = await (_db.select(_db.habitSchedules)
              ..where((s) =>
                  s.habitId.equals(habitId) & s.validTo.isNull() & s.deletedAt.isNull()))
            .get();
        if (open.isEmpty) return;
        final cur = open.first;
        if (cur.daysMask == mask) return;
        final today = _today();
        if (cur.validFrom == today) {
          // نفس يوم الإنشاء/آخر تعديل: نعدّل في مكانه بدل فترة فارغة.
          await (_db.update(_db.habitSchedules)..where((s) => s.id.equals(cur.id))).write(
              HabitSchedulesCompanion(daysMask: Value(mask), updatedAt: Value(DateTime.now())));
          return;
        }
        await (_db.update(_db.habitSchedules)..where((s) => s.id.equals(cur.id))).write(
            HabitSchedulesCompanion(
                validTo: Value(_yesterday()), updatedAt: Value(DateTime.now())));
        await _db.into(_db.habitSchedules).insert(HabitSchedulesCompanion.insert(
            habitId: habitId, daysMask: mask, validFrom: today));
      });

  /// إيقاف مؤقت: لا يُحذف شيء، وأيام الإيقاف لا تُحسب ولا تقطع التسلسل.
  Future<void> pause(String habitId) => _db.transaction(() async {
        await (_db.update(_db.habitSchedules)
              ..where((s) => s.habitId.equals(habitId) & s.validTo.isNull()))
            .write(HabitSchedulesCompanion(
                validTo: Value(_yesterday()), updatedAt: Value(DateTime.now())));
        await (_db.update(_db.habits)..where((h) => h.id.equals(habitId))).write(
            HabitsCompanion(
                pausedAt: Value(DateTime.now()), updatedAt: Value(DateTime.now())));
      });

  /// استئناف العادة بآخر أيام كانت مضبوطة عليها.
  Future<void> resume(String habitId) => _db.transaction(() async {
        final h = await getById(habitId);
        if (h == null || h.pausedAt == null) return;
        final last = await (_db.select(_db.habitSchedules)
              ..where((s) => s.habitId.equals(habitId) & s.deletedAt.isNull())
              ..orderBy([
                (s) => OrderingTerm.desc(s.validFrom),
                (s) => OrderingTerm.desc(CustomExpression<int>('rowid')),
              ])
              ..limit(1))
            .get();
        final mask = last.isEmpty ? 127 : last.first.daysMask;
        await _db.into(_db.habitSchedules).insert(HabitSchedulesCompanion.insert(
            habitId: habitId, daysMask: mask, validFrom: _today()));
        await (_db.update(_db.habits)..where((x) => x.id.equals(habitId))).write(
            HabitsCompanion(
                pausedAt: const Value<DateTime?>(null), updatedAt: Value(DateTime.now())));
      });

  // ---------- التسجيل ----------

  Future<HabitLog?> _logOf(String habitId, String date) => (_db.select(_db.habitLogs)
        ..where((l) => l.habitId.equals(habitId) & l.date.equals(date)))
      .getSingleOrNull();

  Future<void> _deleteLog(String id) =>
      (_db.delete(_db.habitLogs)..where((l) => l.id.equals(id))).go();

  Future<void> _putLog(String habitId, String date, double value, String status) async {
    final existing = await _logOf(habitId, date);
    if (existing == null) {
      await _db.into(_db.habitLogs).insert(HabitLogsCompanion.insert(
          habitId: habitId, date: date, value: Value(value), status: Value(status)));
    } else {
      await (_db.update(_db.habitLogs)..where((l) => l.id.equals(existing.id))).write(
          HabitLogsCompanion(
              value: Value(value), status: Value(status), updatedAt: Value(DateTime.now())));
    }
  }

  /// يسجّل اليوم كمنجز بكامل الهدف، أو يلغي أي تسجيل موجود (أيًا كانت حالته).
  Future<void> toggleDay(String habitId, String date) async {
    final existing = await _logOf(habitId, date);
    if (existing != null) {
      await _deleteLog(existing.id);
      return;
    }
    final h = await getById(habitId);
    await _putLog(habitId, date, h?.targetValue ?? 1, 'done');
  }

  /// يسجّل كمية اليوم (عدد/مدة): تامّ إن بلغ الهدف، جزئي إن كان أقل، ويُمسح إن كان 0.
  Future<void> logValue(String habitId, String date, double value) async {
    final existing = await _logOf(habitId, date);
    if (value <= 0) {
      if (existing != null) await _deleteLog(existing.id);
      return;
    }
    final h = await getById(habitId);
    final target = (h == null || h.targetValue <= 0) ? 1.0 : h.targetValue;
    await _putLog(habitId, date, value, value >= target ? 'done' : 'partial');
  }

  /// يوم إجازة/استثناء: لا يُحسب عليك ولا يقطع التسلسل. [excused] = false يلغيه.
  Future<void> setExcused(String habitId, String date, bool excused) async {
    final existing = await _logOf(habitId, date);
    if (excused) {
      await _putLog(habitId, date, 0, 'excused');
    } else if (existing != null && existing.status == 'excused') {
      await _deleteLog(existing.id);
    }
  }
}
