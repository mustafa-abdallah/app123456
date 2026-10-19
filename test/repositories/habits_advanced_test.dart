import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/core/format.dart';
import 'package:knowledge_app/database/database.dart';
import 'package:knowledge_app/repositories/habits_repository.dart';

void main() {
  late AppDatabase db;
  late HabitsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = HabitsRepository(db);
  });
  tearDown(() => db.close());

  final now = DateTime.now();
  final todayKey = formatDate(now);
  final yesterdayKey = formatDate(DateTime(now.year, now.month, now.day - 1));
  const day = '2026-10-19';

  Future<List<HabitSchedule>> spans(String id) =>
      (db.select(db.habitSchedules)..where((s) => s.habitId.equals(id))).get();
  Future<List<HabitLog>> logs(String id) =>
      (db.select(db.habitLogs)..where((l) => l.habitId.equals(id))).get();

  test('إنشاء عادة بهدف عددي ووحدة', () async {
    final id = await repo.create('قراءة', kind: 'count', target: 10, unit: 'صفحة');
    final h = (await repo.getById(id))!;
    expect(h.kind, 'count');
    expect(h.targetValue, 10);
    expect(h.unit, 'صفحة');
    expect((await spans(id)).single.daysMask, 127);
  });

  test('تسجيل الكمية: جزئي ثم تامّ ثم مسح', () async {
    final id = await repo.create('قراءة', kind: 'count', target: 10, unit: 'صفحة');
    await repo.logValue(id, day, 4);
    expect((await logs(id)).single.status, 'partial');
    expect((await logs(id)).single.value, 4);

    await repo.logValue(id, day, 12);
    expect((await logs(id)).length, 1); // تحديث لا تكرار
    expect((await logs(id)).single.status, 'done');

    await repo.logValue(id, day, 0);
    expect(await logs(id), isEmpty);
  });

  test('تبديل اليوم لعادة عددية يسجّل الهدف كاملًا، ولعادة نعم/لا يسجّل 1', () async {
    final c = await repo.create('ماء', kind: 'count', target: 8, unit: 'كوب');
    final k = await repo.create('ورد');
    await repo.toggleDay(c, day);
    await repo.toggleDay(k, day);
    expect((await logs(c)).single.value, 8);
    expect((await logs(c)).single.status, 'done');
    expect((await logs(k)).single.value, 1);
    await repo.toggleDay(c, day);
    expect(await logs(c), isEmpty);
  });

  test('تغيير الهدف يعيد تصنيف السجلات القديمة دون المساس بالقيم', () async {
    final id = await repo.create('قراءة', kind: 'count', target: 10, unit: 'صفحة');
    await repo.logValue(id, day, 6); // جزئي
    await repo.setGoal(id, kind: 'count', target: 5, unit: 'صفحة');
    final l = (await logs(id)).single;
    expect(l.value, 6);
    expect(l.status, 'done'); // 6 >= 5
  });

  test('يوم الإجازة: يُسجَّل ويُلغى، ولا يمسح سجلًا آخر', () async {
    final id = await repo.create('ورد');
    await repo.setExcused(id, day, true);
    expect((await logs(id)).single.status, 'excused');
    await repo.setExcused(id, day, false);
    expect(await logs(id), isEmpty);

    await repo.toggleDay(id, day); // منجز
    await repo.setExcused(id, day, false); // إلغاء إجازة غير موجودة
    expect((await logs(id)).single.status, 'done');
  });

  test('تعديل الأيام في يوم الإنشاء يُعدَّل في مكانه', () async {
    final id = await repo.create('ورد');
    await repo.setDays(id, 21);
    final s = await spans(id);
    expect(s.length, 1);
    expect(s.single.daysMask, 21);
  });

  test('تعديل الأيام لاحقًا يغلق الفترة القديمة ويفتح جديدة دون المساس بالماضي', () async {
    final id = await repo.create('ورد');
    final fiveDaysAgo = formatDate(DateTime(now.year, now.month, now.day - 5));
    await (db.update(db.habitSchedules)..where((s) => s.habitId.equals(id)))
        .write(HabitSchedulesCompanion(validFrom: Value(fiveDaysAgo)));

    await repo.setDays(id, 21);
    final s = await spans(id);
    expect(s.length, 2);
    final old = s.firstWhere((x) => x.validTo != null);
    final cur = s.firstWhere((x) => x.validTo == null);
    expect(old.daysMask, 127);
    expect(old.validFrom, fiveDaysAgo);
    expect(old.validTo, yesterdayKey);
    expect(cur.daysMask, 21);
    expect(cur.validFrom, todayKey);
  });

  test('الإيقاف المؤقت والاستئناف يحفظان الأيام والسجل', () async {
    final id = await repo.create('ورد', daysMask: 21);
    await repo.toggleDay(id, day);

    await repo.pause(id);
    expect((await repo.getById(id))!.pausedAt, isNotNull);
    expect((await spans(id)).where((x) => x.validTo == null), isEmpty);
    expect((await logs(id)).length, 1); // السجل باقٍ

    await repo.setDays(id, 127); // لا أثر أثناء الإيقاف
    expect((await spans(id)).where((x) => x.validTo == null), isEmpty);

    await repo.resume(id);
    expect((await repo.getById(id))!.pausedAt, isNull);
    final open = (await spans(id)).where((x) => x.validTo == null).single;
    expect(open.daysMask, 21); // نفس الأيام السابقة
    expect(open.validFrom, todayKey);
    expect((await logs(id)).length, 1);
  });

  test('استئناف عادة غير متوقفة لا يفعل شيئًا', () async {
    final id = await repo.create('ورد');
    await repo.resume(id);
    expect((await spans(id)).length, 1);
  });
}
