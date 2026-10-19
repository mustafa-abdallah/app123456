import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/database/database.dart';
import 'package:knowledge_app/repositories/folders_repository.dart';
import 'package:knowledge_app/repositories/habits_repository.dart';
import 'package:knowledge_app/repositories/notes_repository.dart';
import 'package:knowledge_app/repositories/tasks_repository.dart';
import 'package:knowledge_app/services/backup_service.dart';

Future<void> _seed(AppDatabase db) async {
  final parent = await FoldersRepository(db).create('أب');
  final child = await FoldersRepository(db).create('ابن', parentId: parent);
  final notes = NotesRepository(db);
  final n = await notes.create(folderId: child);
  await notes.save(n, title: 'درس النحو', body: 'الفاعل مرفوع [[ملاحظة أخرى]]');
  await notes.addTag(n, 'نحو');
  await TasksRepository(db).create('مهمة', priority: 2, dueAt: DateTime(2026, 10, 20, 9));
  final habits = HabitsRepository(db);
  final h = await habits.create('ورد');
  await habits.toggleDay(h, '2026-10-19');
}

void main() {
  late AppDatabase src;
  late AppDatabase dst;

  setUp(() {
    src = AppDatabase(NativeDatabase.memory());
    dst = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await src.close();
    await dst.close();
  });

  test('التصدير ثم الاستيراد في قاعدة فارغة يحفظ كل شيء ويعمل البحث', () async {
    await _seed(src);
    final json = await BackupService(src).exportJson();
    final n = await BackupService(dst).importJson(json);
    expect(n, greaterThan(0));

    final notes = await dst.select(dst.notes).get();
    expect(notes.single.title, 'درس النحو');
    expect((await dst.searchNotes('النحو')).length, 1);
    expect((await NotesRepository(dst).tagsFor(notes.single.id)).single.name, 'نحو');

    final task = (await dst.select(dst.tasks).get()).single;
    expect(task.priority, 2);
    expect(task.dueAt!.millisecondsSinceEpoch,
        DateTime(2026, 10, 20, 9).millisecondsSinceEpoch);
    expect((await dst.select(dst.habitLogs).get()).length, 1);
    expect((await dst.select(dst.folders).get()).length, 2);
  });

  test('الاستيراد مرتين لا يكرر السجلات', () async {
    await _seed(src);
    final json = await BackupService(src).exportJson();
    final svc = BackupService(dst);
    await svc.importJson(json);
    await svc.importJson(json);
    expect((await dst.select(dst.notes).get()).length, 1);
    expect((await dst.select(dst.noteVersions).get()).length, 1);
    expect((await dst.select(dst.habitLogs).get()).length, 1);
  });

  test('الاستيراد يدمج ولا يحذف الموجود', () async {
    await _seed(src);
    await NotesRepository(dst).create(title: 'موجودة مسبقًا');
    await BackupService(dst).importJson(await BackupService(src).exportJson());
    expect((await dst.select(dst.notes).get()).length, 2);
  });

  test('ترتيب المجلدات في الملف لا يهم (الابن قبل الأب)', () async {
    await _seed(src);
    final m = jsonDecode(await BackupService(src).exportJson()) as Map<String, dynamic>;
    final t = m['tables'] as Map<String, dynamic>;
    t['folders'] = (t['folders'] as List).reversed.toList();
    await BackupService(dst).importJson(jsonEncode(m));
    expect((await dst.select(dst.folders).get()).length, 2);
  });

  test('المدخلات الخاطئة تُرفض برسالة ولا تغيّر شيئًا', () async {
    final svc = BackupService(dst);
    expect(() => svc.importJson('ليس json'), throwsFormatException);
    expect(() => svc.importJson('{"app":"other","version":1}'), throwsFormatException);
    expect(() => svc.importJson('{"app":"knowledge_app","version":99,"tables":{}}'),
        throwsFormatException);
    expect(await dst.select(dst.notes).get(), isEmpty);
  });
}
