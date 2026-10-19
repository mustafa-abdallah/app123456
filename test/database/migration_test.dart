import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/database/database.dart';
import 'package:knowledge_app/repositories/notes_repository.dart';
import 'package:knowledge_app/repositories/settings_repository.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kapp_mig_');
    file = File('${dir.path}/test.db');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  AppDatabase open() => AppDatabase(NativeDatabase(file));

  Future<int> userVersion(AppDatabase db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version');

  test('الترحيل من 1 إلى 2 يحافظ على كل البيانات وينشئ جدول الإعدادات', () async {
    // نحاكي قاعدة قديمة: إصدار 1 بلا جدول app_settings، وفيها بيانات حقيقية.
    var db = open();
    final notes = NotesRepository(db);
    final id = await notes.create();
    await notes.save(id, title: 'ملاحظة قديمة', body: 'محتوى باقٍ بعد التحديث');
    await notes.addTag(id, 'نحو');
    await db.customStatement('DROP TABLE app_settings');
    await db.customStatement('PRAGMA user_version = 1');
    expect(await userVersion(db), 1);
    await db.close();

    // إعادة الفتح بالكود الجديد = ترحيل فعلي (لا حذف ولا إعادة بناء).
    db = open();
    final old = await db.select(db.notes).get();
    expect(old.single.title, 'ملاحظة قديمة');
    expect(old.single.bodyMd, 'محتوى باقٍ بعد التحديث');
    expect((await NotesRepository(db).tagsFor(id)).single.name, 'نحو');
    expect((await db.searchNotes('باقٍ')).length, 1);

    final settings = SettingsRepository(db);
    await settings.set('k', 'v');
    expect(await settings.get('k'), 'v');
    expect(await userVersion(db), db.schemaVersion);
    await db.close();
  });

  test('إعادة فتح قاعدة محدّثة لا تعيد الترحيل ولا تمس البيانات', () async {
    var db = open();
    await SettingsRepository(db).set('a', '1');
    await db.close();
    db = open();
    expect(await SettingsRepository(db).get('a'), '1');
    await db.close();
  });
}
