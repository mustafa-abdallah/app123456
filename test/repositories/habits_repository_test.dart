import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('إنشاء عادة ينشئ جدولها الافتراضي (كل الأيام)', () async {
    final id = await repo.create('ورد');
    expect((await repo.watchActive().first).single.name, 'ورد');
    expect((await repo.masks())[id], 127);
  });

  test('تبديل اليوم يسجّل ثم يلغي دون خطأ التكرار', () async {
    final id = await repo.create('ورد');
    await repo.toggleDay(id, '2026-10-19');
    expect((await repo.watchLogsSince('2026-10-01').first).length, 1);
    await repo.toggleDay(id, '2026-10-19');
    expect(await repo.watchLogsSince('2026-10-01').first, isEmpty);
  });

  test('حذف العادة منطقي ويبقي سجلها', () async {
    final id = await repo.create('ورد');
    await repo.toggleDay(id, '2026-10-19');
    await repo.softDelete(id);
    expect(await repo.watchActive().first, isEmpty);
    expect((await db.select(db.habitLogs).get()).length, 1);
  });

  test('إعادة التسمية تحفظ السجل', () async {
    final id = await repo.create('ورد');
    await repo.toggleDay(id, '2026-10-19');
    await repo.rename(id, 'ورد القرآن');
    expect((await repo.watchActive().first).single.name, 'ورد القرآن');
    expect((await repo.watchLogsSince('2026-10-01').first).length, 1);
  });
}
