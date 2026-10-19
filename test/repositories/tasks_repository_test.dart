import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/database/database.dart';
import 'package:knowledge_app/repositories/tasks_repository.dart';

void main() {
  late AppDatabase db;
  late TasksRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TasksRepository(db);
  });
  tearDown(() => db.close());

  test('إنجاز المهمة ينقلها من النشطة إلى المنجزة وبالعكس', () async {
    final id = await repo.create('اشترِ خبزًا');
    var t = (await repo.getById(id))!;
    expect((await repo.watch(TaskView.active).first).length, 1);

    await repo.toggle(t);
    t = (await repo.getById(id))!;
    expect(t.status, 'done');
    expect(t.completedAt, isNotNull);
    expect(await repo.watch(TaskView.active).first, isEmpty);
    expect((await repo.watch(TaskView.done).first).length, 1);

    await repo.toggle(t);
    t = (await repo.getById(id))!;
    expect(t.status, 'todo');
    expect(t.completedAt, isNull);
  });

  test('الأولوية الأعلى تظهر أولًا', () async {
    await repo.create('عادية');
    await repo.create('عاجلة', priority: 2);
    final list = await repo.watch(TaskView.active).first;
    expect(list.first.title, 'عاجلة');
  });

  test('الحذف المنطقي والتراجع، وإزالة تاريخ الاستحقاق', () async {
    final id = await repo.create('م', dueAt: DateTime(2026, 10, 20));
    await repo.softDelete(id);
    expect(await repo.watch(TaskView.active).first, isEmpty);
    await repo.restore(id);
    expect((await repo.watch(TaskView.active).first).length, 1);

    await repo.update(id, title: 'م2', priority: 1, dueAt: null);
    final t = (await repo.getById(id))!;
    expect(t.title, 'م2');
    expect(t.dueAt, isNull);
  });
}
