import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/database/database.dart';
import 'package:knowledge_app/repositories/notes_repository.dart';

void main() {
  late AppDatabase db;
  late NotesRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = NotesRepository(db);
  });
  tearDown(() => db.close());

  test('الحفظ الأول ينشئ نسخة، والتعديل السريع لا يكرر النسخ', () async {
    final id = await repo.create();
    await repo.save(id, title: 'أ', body: 'ب');
    await repo.save(id, title: 'أ', body: 'ج');
    expect((await repo.versions(id)).length, 1);
    expect((await repo.getById(id))!.bodyMd, 'ج');
  });

  test('الملاحظة الفارغة تُحذف عند الخروج، وغير الفارغة تبقى', () async {
    final empty = await repo.create();
    final full = await repo.create();
    await repo.save(full, title: 'عنوان', body: '');
    await repo.deleteIfEmpty(empty);
    await repo.deleteIfEmpty(full);
    expect(await repo.getById(empty), isNull);
    expect(await repo.getById(full), isNotNull);
  });

  test('الحذف المنطقي والتراجع عنه', () async {
    final id = await repo.create();
    await repo.save(id, title: 'x', body: 'y');
    await repo.softDelete(id);
    expect(await repo.watch(const NotesFilter()).first, isEmpty);
    await repo.restore(id);
    expect((await repo.watch(const NotesFilter()).first).length, 1);
  });
}
