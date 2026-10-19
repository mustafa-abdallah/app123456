import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/database/database.dart';
import 'package:knowledge_app/repositories/folders_repository.dart';
import 'package:knowledge_app/repositories/habits_repository.dart';
import 'package:knowledge_app/repositories/notes_repository.dart';
import 'package:knowledge_app/repositories/settings_repository.dart';
import 'package:knowledge_app/repositories/tasks_repository.dart';
import 'package:knowledge_app/services/backup_service.dart';

Future<void> _seed(AppDatabase db) async {
  final f = await FoldersRepository(db).create('مجلد');
  final notes = NotesRepository(db);
  final n = await notes.create(folderId: f);
  await notes.save(n, title: 'درس النحو', body: 'الفاعل مرفوع');
  await TasksRepository(db).create('مهمة');
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

  test('الفحص يقرأ الملخص والمجموع الاختباري دون تغيير شيء', () async {
    await _seed(src);
    final json = await BackupService(src).exportJson();
    final info = BackupService(dst).inspect(json);
    expect(info.version, BackupService.formatVersion);
    expect(info.verified, isTrue);
    expect(info.exportedAt, isNotNull);
    expect(info.counts['notes'], 1);
    expect(info.counts['tasks'], 1);
    expect(info.counts['habitLogs'], 1);
    expect(await dst.select(dst.notes).get(), isEmpty);
  });

  test('أي تعديل في محتوى الملف يُكتشف ويُرفض الاستيراد', () async {
    await _seed(src);
    final json = await BackupService(src).exportJson();
    final tampered = json.replaceFirst('درس النحو', 'درس مُعدَّل');
    expect(tampered, isNot(json));
    final svc = BackupService(dst);
    expect(() => svc.inspect(tampered), throwsFormatException);
    await expectLater(svc.importJson(tampered), throwsFormatException);
    expect(await dst.select(dst.notes).get(), isEmpty);
  });

  test('ملف مقتطع (ناقص السجلات) يُكتشف عبر الأعداد حتى مع مجموع اختباري صحيح', () async {
    await _seed(src);
    final m = jsonDecode(await BackupService(src).exportJson()) as Map<String, dynamic>;
    final t = m['tables'] as Map<String, dynamic>;
    t['notes'] = <dynamic>[]; // حذف الملاحظات من الملف
    m['checksum'] = sha256.convert(utf8.encode(jsonEncode(t))).toString();
    expect(() => BackupService(dst).inspect(jsonEncode(m)), throwsFormatException);
  });

  test('نسخة الإصدار 1 بلا مجموع اختباري ما زالت مقبولة', () async {
    await _seed(src);
    final m = jsonDecode(await BackupService(src).exportJson()) as Map<String, dynamic>;
    m['version'] = 1;
    m.remove('checksum');
    m.remove('counts');
    final svc = BackupService(dst);
    final info = svc.inspect(jsonEncode(m));
    expect(info.verified, isFalse);
    expect(await svc.importJson(jsonEncode(m)), greaterThan(0));
    expect((await dst.select(dst.notes).get()).length, 1);
  });

  test('الاستبدال يمسح الموجود ويستعيد النسخة كاملة', () async {
    await _seed(src);
    await NotesRepository(dst).create(title: 'دخيلة ستُمسح');
    await HabitsRepository(dst).create('عادة دخيلة');
    await BackupService(dst).importJson(await BackupService(src).exportJson(), replace: true);

    final notes = await dst.select(dst.notes).get();
    expect(notes.single.title, 'درس النحو');
    expect((await dst.select(dst.habits).get()).single.name, 'ورد');
    expect((await dst.searchNotes('النحو')).length, 1);
    expect(await dst.searchNotes('دخيلة'), isEmpty); // الفهرس تبع الحذف أيضًا
  });

  test('فشل الاستبدال في منتصفه يتراجع عن كل شيء ولا يمسح البيانات', () async {
    await NotesRepository(dst).create(title: 'يجب أن تبقى');
    final bad = jsonEncode({
      'app': BackupService.appId,
      'version': 1,
      'tables': {
        'notes': [
          {'id': 5} // سجل تالف
        ],
      },
    });
    await expectLater(BackupService(dst).importJson(bad, replace: true), throwsFormatException);
    final left = await dst.select(dst.notes).get();
    expect(left.single.title, 'يجب أن تبقى');
  });

  test('الإعدادات تُنسخ، ومفاتيح الجهاز backup.* لا تُنسخ ولا تُمسح بالاستبدال', () async {
    final s = SettingsRepository(src);
    await s.set('ui.theme', 'dark');
    await s.markExported();
    final json = await BackupService(src).exportJson();

    final d = SettingsRepository(dst);
    await d.markExported(DateTime(2026, 1, 1));
    await BackupService(dst).importJson(json, replace: true);

    expect(await d.get('ui.theme'), 'dark');
    expect(await d.get(SettingsRepository.lastExportKey), isNotNull);
    expect(DateTime.parse((await d.get(SettingsRepository.lastExportKey))!).year, 2026);
  });
}
