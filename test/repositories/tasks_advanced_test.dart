import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/core/format.dart';
import 'package:knowledge_app/database/database.dart';
import 'package:knowledge_app/repositories/notes_repository.dart';
import 'package:knowledge_app/repositories/tasks_repository.dart';

void main() {
  late AppDatabase db;
  late TasksRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TasksRepository(db);
  });
  tearDown(() => db.close());

  Future<Task> get(String id) async => (await repo.getById(id))!;

  test('المهام الفرعية لا تظهر في القوائم الرئيسية وتظهر داخل أمها بترتيب الإضافة', () async {
    final p = await repo.create('أم');
    await repo.create('ب', parentTaskId: p);
    await repo.create('أ', parentTaskId: p);
    expect((await repo.watch(TaskView.active).first).map((t) => t.title), ['أم']);
    expect((await repo.watchSubtasks(p).first).map((t) => t.title), ['ب', 'أ']);
  });

  test('تبويب المتأخرة: قبل اليوم فقط وغير المنجزة فقط', () async {
    final today = startOfDay(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final late1 = await repo.create('متأخرة', dueAt: yesterday);
    await repo.create('اليوم', dueAt: today);
    await repo.create('بلا موعد');
    final doneLate = await repo.create('منجزة متأخرة', dueAt: yesterday);
    await repo.toggle(await get(doneLate));

    final overdue = await repo.watch(TaskView.overdue).first;
    expect(overdue.map((t) => t.id), [late1]);
  });

  test('نقل المتأخرة إلى اليوم يحفظ الوقت ويُرجع العدد', () async {
    final today = startOfDay(DateTime.now());
    final y = DateTime(today.year, today.month, today.day - 3, 14, 30);
    final id = await repo.create('م', dueAt: y);
    expect(await repo.moveOverdueToToday(), 1);
    final t = await get(id);
    expect(startOfDay(t.dueAt!), today);
    expect(t.dueAt!.hour, 14);
    expect(t.dueAt!.minute, 30);
    expect(await repo.watch(TaskView.overdue).first, isEmpty);
    expect(await repo.moveOverdueToToday(), 0);
  });

  test('إنجاز مهمة متكررة ينشئ نسختها التالية مع مهامها الفرعية غير منجزة', () async {
    final id = await repo.create('ورد أسبوعي',
        dueAt: DateTime(2099, 1, 1, 10, 0), recurrenceRule: 'weekly');
    final sub = await repo.create('بند', parentTaskId: id);
    await repo.toggle(await get(sub)); // البند منجز في الدورة الحالية

    await repo.toggle(await get(id));
    final all = await db.select(db.tasks).get();
    final parents = all.where((t) => t.parentTaskId == null).toList();
    expect(parents.length, 2);
    final next = parents.firstWhere((t) => t.status != 'done');
    expect(next.title, 'ورد أسبوعي');
    expect(next.dueAt, DateTime(2099, 1, 8, 10, 0));
    expect(next.recurrenceRule, 'weekly');

    final nextSubs = await repo.watchSubtasks(next.id).first;
    expect(nextSubs.single.title, 'بند');
    expect(nextSubs.single.status, 'todo');
  });

  test('إعادة فتح مهمة منجزة لا تنشئ نسخة جديدة', () async {
    final id = await repo.create('م', dueAt: DateTime(2099, 1, 1), recurrenceRule: 'daily');
    await repo.toggle(await get(id));
    await repo.toggle(await get(id)); // إعادة فتح
    expect((await db.select(db.tasks).get()).length, 2);
  });

  test('الاعتمادية تمنع الإنجاز حتى تُنجز المهمة السابقة', () async {
    final a = await repo.create('أ');
    final b = await repo.create('ب');
    expect(await repo.addDependency(a, b), isTrue); // أ تعتمد على ب

    var r = await repo.toggle(await get(a));
    expect(r.ok, isFalse);
    expect(r.blockers.single.id, b);
    expect((await get(a)).status, 'todo');

    await repo.toggle(await get(b));
    r = await repo.toggle(await get(a));
    expect(r.ok, isTrue);
    expect((await get(a)).status, 'done');
  });

  test('الاعتماد الذاتي أو الدائري مرفوض، والإزالة تعمل', () async {
    final a = await repo.create('أ');
    final b = await repo.create('ب');
    final c = await repo.create('ج');
    expect(await repo.addDependency(a, a), isFalse);
    expect(await repo.addDependency(a, b), isTrue);
    expect(await repo.addDependency(b, c), isTrue);
    expect(await repo.addDependency(c, a), isFalse); // أ→ب→ج→أ
    expect((await repo.dependenciesOf(a)).single.id, b);
    await repo.removeDependency(a, b);
    expect(await repo.dependenciesOf(a), isEmpty);
    expect(await repo.addDependency(c, a), isTrue); // لم يعد هناك دورة
  });

  test('ربط المهمة بملاحظات وفكّه، والملاحظة المحذوفة لا تظهر', () async {
    final notes = NotesRepository(db);
    final n1 = await notes.create(title: 'درس');
    final n2 = await notes.create(title: 'كتاب');
    final t = await repo.create('م');
    await repo.linkNote(t, n1);
    await repo.linkNote(t, n1); // لا تكرار
    await repo.linkNote(t, n2);
    expect((await repo.watchNotes(t).first).map((n) => n.title), ['درس', 'كتاب']);

    await repo.unlinkNote(t, n1);
    await notes.softDelete(n2);
    expect(await repo.watchNotes(t).first, isEmpty);
  });

  test('openTasks يستثني المهمة نفسها والمنجزة والفرعية', () async {
    final a = await repo.create('أ');
    final b = await repo.create('ب');
    final c = await repo.create('ج');
    await repo.create('فرعية', parentTaskId: a);
    await repo.toggle(await get(c));
    expect((await repo.openTasks(excludeId: a)).map((t) => t.id), [b]);
  });
}
