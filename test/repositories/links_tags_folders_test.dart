import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/core/wiki_links.dart';
import 'package:knowledge_app/database/database.dart';
import 'package:knowledge_app/repositories/folders_repository.dart';
import 'package:knowledge_app/repositories/notes_repository.dart';

void main() {
  late AppDatabase db;
  late NotesRepository repo;
  late FoldersRepository folders;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = NotesRepository(db);
    folders = FoldersRepository(db);
  });
  tearDown(() => db.close());

  test('استخراج الروابط وتحويلها لمعاينة Markdown', () {
    expect(extractLinkTitles('[[x]] و [[x|y]] و [[ z ]]'), ['x', 'z']);
    expect(linksToMarkdown('[[فقه|الفقه]]'),
        '[الفقه](note://${Uri.encodeComponent('فقه')})');
  });

  test('الروابط الواردة تُحسب من العنوان وتبقى صحيحة بعد تغييره', () async {
    final a = await repo.create();
    final b = await repo.create();
    await repo.save(a, title: 'فقه', body: '');
    await repo.save(b, title: 'درس', body: 'راجع [[فقه]] و [[فقه|الفقه]]');
    expect((await repo.backlinks(a)).map((n) => n.id), [b]);
    expect((await repo.findByTitle('فقه'))!.id, a);
    await repo.save(a, title: 'أصول', body: '');
    expect(await repo.backlinks(a), isEmpty);
  });

  test('الوسوم: لا تكرار، وعدّاد، ومرشّح، وإزالة', () async {
    final n = await repo.create();
    await repo.save(n, title: 'x', body: 'y');
    await repo.addTag(n, '#فقه');
    await repo.addTag(n, 'فقه');
    final tags = await repo.tagsFor(n);
    expect(tags.length, 1);
    expect(tags.single.name, 'فقه');
    expect((await repo.tagsWithCounts()).single.count, 1);
    expect((await repo.watch(NotesFilter(tagId: tags.single.id)).first).length, 1);
    await repo.removeTag(n, tags.single.id);
    expect((await repo.tagsWithCounts()).single.count, 0);
  });

  test('حذف المجلد ينقل محتواه إلى المجلد الأعلى', () async {
    final p = await folders.create('أ');
    final c = await folders.create('ب', parentId: p);
    final n = await repo.create(folderId: c);
    expect((await folders.allWithPath()).map((e) => e.path), ['أ', 'أ / ب']);
    await folders.delete(c);
    expect((await repo.getById(n))!.folderId, p);
    await folders.delete(p);
    expect((await repo.getById(n))!.folderId, isNull);
    expect(await folders.allWithPath(), isEmpty);
  });
}
