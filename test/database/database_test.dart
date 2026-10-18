import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/database/database.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kapp_');
    file = File('${dir.path}/test.db');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  AppDatabase open() => AppDatabase(NativeDatabase(file));

  test('الملاحظة تبقى بعد إغلاق قاعدة البيانات وإعادة فتحها', () async {
    var db = open();
    await db.into(db.notes).insert(
        NotesCompanion.insert(title: const Value('درس النحو'), bodyMd: const Value('الفاعل مرفوع')));
    await db.close();

    db = open();
    final all = await db.select(db.notes).get();
    expect(all.single.title, 'درس النحو');
    await db.close();
  });

  test('البحث النصي يجد الملاحظة ويتحدث بعد التعديل', () async {
    final db = open();
    final id = 'n1';
    await db.into(db.notes).insert(NotesCompanion.insert(
        id: Value(id), title: const Value('كتاب'), bodyMd: const Value('hello world')));
    expect((await db.searchNotes('hel')).length, 1);

    await (db.update(db.notes)..where((n) => n.id.equals(id)))
        .write(const NotesCompanion(bodyMd: Value('goodbye')));
    expect(await db.searchNotes('hello'), isEmpty);
    expect((await db.searchNotes('goodbye')).length, 1);
    await db.close();
  });

  test('تعديل اسم العادة لا يفقد سجلها', () async {
    final db = open();
    await db.into(db.habits).insert(HabitsCompanion.insert(id: const Value('h1'), name: 'ورد'));
    await db.into(db.habitLogs).insert(
        HabitLogsCompanion.insert(habitId: 'h1', date: '2026-10-17'));
    await (db.update(db.habits)..where((h) => h.id.equals('h1')))
        .write(const HabitsCompanion(name: Value('ورد القرآن')));
    expect((await db.select(db.habitLogs).get()).length, 1);
    await db.close();
  });

  test('لا يمكن تسجيل العادة مرتين في اليوم نفسه', () async {
    final db = open();
    await db.into(db.habits).insert(HabitsCompanion.insert(id: const Value('h1'), name: 'ورد'));
    await db.into(db.habitLogs).insert(
        HabitLogsCompanion.insert(habitId: 'h1', date: '2026-10-17'));
    expect(
        () => db.into(db.habitLogs).insert(
            HabitLogsCompanion.insert(habitId: 'h1', date: '2026-10-17')),
        throwsA(anything));
    await db.close();
  });
}
