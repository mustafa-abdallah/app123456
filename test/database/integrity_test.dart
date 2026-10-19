import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/database/database.dart';
import 'package:knowledge_app/repositories/notes_repository.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('فحص السلامة يُرجع ok لقاعدة سليمة', () async {
    expect(await db.integrityCheck(), 'ok');
  });

  test('إعادة بناء فهرس البحث تصلح فهرسًا فارغًا أو تالفًا', () async {
    final repo = NotesRepository(db);
    final id = await repo.create();
    await repo.save(id, title: 'عنوان', body: 'كلمة مميزة');
    expect((await db.searchNotes('مميزة')).length, 1);

    // نحاكي تلف الفهرس بمسحه مع بقاء الملاحظات.
    await db.customStatement("INSERT INTO notes_fts(notes_fts) VALUES('delete-all')");
    expect(await db.searchNotes('مميزة'), isEmpty);

    await db.rebuildSearchIndex();
    expect((await db.searchNotes('مميزة')).length, 1);
  });
}
