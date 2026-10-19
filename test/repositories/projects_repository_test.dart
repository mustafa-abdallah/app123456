import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/database/database.dart';
import 'package:knowledge_app/repositories/projects_repository.dart';
import 'package:knowledge_app/repositories/tasks_repository.dart';

void main() {
  late AppDatabase db;
  late ProjectsRepository projects;
  late TasksRepository tasks;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    projects = ProjectsRepository(db);
    tasks = TasksRepository(db);
  });
  tearDown(() => db.close());

  test('إنشاء تصنيف وعرضه بالترتيب', () async {
    await projects.create('عمل');
    await projects.create('بيت');
    final list = await projects.watchActive().first;
    expect(list.map((p) => p.name).toSet(), {'عمل', 'بيت'});
  });

  test('حذف التصنيف لا يحذف مهامه بل يفصلها عنه', () async {
    final pid = await projects.create('دراسة');
    final tid = await tasks.create('مذاكرة', projectId: pid);
    expect((await tasks.getById(tid))!.projectId, pid);

    await projects.delete(pid);
    expect(await projects.watchActive().first, isEmpty);
    final t = (await tasks.getById(tid))!;
    expect(t.projectId, isNull);
    expect((await tasks.watch(TaskView.active).first).length, 1);
  });

  test('تصفية المهام حسب التصنيف', () async {
    final a = await projects.create('أ');
    await tasks.create('في أ', projectId: a);
    await tasks.create('بلا تصنيف');
    expect((await tasks.watch(TaskView.active, projectId: a).first).single.title, 'في أ');
    expect((await tasks.watch(TaskView.active).first).length, 2);
  });

  test('تصفية المهام حسب اليوم تشمل كل ساعات اليوم فقط', () async {
    await tasks.create('صباحًا', dueAt: DateTime(2026, 10, 20, 8));
    await tasks.create('ليلًا', dueAt: DateTime(2026, 10, 20, 23, 59));
    await tasks.create('غدًا', dueAt: DateTime(2026, 10, 21, 0, 0));
    await tasks.create('بلا موعد');
    final list =
        await tasks.watch(TaskView.active, day: DateTime(2026, 10, 20)).first;
    expect(list.map((t) => t.title).toSet(), {'صباحًا', 'ليلًا'});
  });

  test('تغيير تصنيف مهمة عند التعديل', () async {
    final a = await projects.create('أ');
    final id = await tasks.create('م');
    await tasks.update(id, title: 'م', priority: 0, projectId: a);
    expect((await tasks.getById(id))!.projectId, a);
    await tasks.update(id, title: 'م', priority: 0, projectId: null);
    expect((await tasks.getById(id))!.projectId, isNull);
  });
}
