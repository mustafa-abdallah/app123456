import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import '../core/recurrence.dart';
import '../database/database.dart';

enum TaskView { active, overdue, done }

/// نتيجة محاولة إنجاز مهمة: إن وُجدت [blockers] لم تُنجز المهمة.
class CompleteResult {
  const CompleteResult(this.blockers);
  final List<Task> blockers;
  bool get ok => blockers.isEmpty;
}

/// المصدر الوحيد لبيانات المهام.
class TasksRepository {
  TasksRepository(this._db);
  final AppDatabase _db;

  static const priorityLabels = ['عادية', 'متوسطة', 'عالية'];

  // ---------- القراءة ----------

  /// المهام الرئيسية فقط (المهام الفرعية تظهر داخل أمها).
  /// [projectId]: تصنيف معيّن. [day]: المهام المستحقة في هذا اليوم فقط (لا يسري على المتأخرة).
  Stream<List<Task>> watch(TaskView view, {String? projectId, DateTime? day}) {
    final q = _db.select(_db.tasks)
      ..where((t) => t.deletedAt.isNull() & t.parentTaskId.isNull());
    if (projectId != null) {
      q.where((t) => t.projectId.equals(projectId));
    }
    if (day != null && view != TaskView.overdue) {
      final start = DateTime(day.year, day.month, day.day);
      final end = DateTime(day.year, day.month, day.day + 1);
      q.where((t) =>
          t.dueAt.isBiggerOrEqualValue(start) & t.dueAt.isSmallerThanValue(end));
    }
    switch (view) {
      case TaskView.done:
        q
          ..where((t) => t.status.equals('done'))
          ..orderBy([(t) => OrderingTerm.desc(t.completedAt)]);
      case TaskView.overdue:
        final start = startOfDay(DateTime.now());
        q
          ..where((t) =>
              t.status.equals('done').not() & t.dueAt.isSmallerThanValue(start))
          ..orderBy([
            (t) => OrderingTerm.asc(t.dueAt),
            (t) => OrderingTerm.desc(t.priority),
          ]);
      case TaskView.active:
        q
          ..where((t) => t.status.equals('done').not())
          ..orderBy([
            (t) => OrderingTerm.desc(t.priority),
            (t) => OrderingTerm.desc(t.createdAt),
          ]);
    }
    return q.watch();
  }

  Future<Task?> getById(String id) =>
      (_db.select(_db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<Task?> watchOne(String id) =>
      (_db.select(_db.tasks)..where((t) => t.id.equals(id))).watchSingleOrNull();

  /// المهام الفرعية بترتيب الإضافة.
  Stream<List<Task>> watchSubtasks(String parentId) => (_db.select(_db.tasks)
        ..where((t) => t.parentTaskId.equals(parentId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(CustomExpression<int>('rowid'))]))
      .watch();

  // ---------- الإنشاء والتعديل ----------

  Future<String> create(String title,
      {int priority = 0,
      DateTime? dueAt,
      String? projectId,
      String? parentTaskId,
      String? recurrenceRule}) async {
    final id = const Uuid().v4();
    await _db.into(_db.tasks).insert(TasksCompanion.insert(
          id: Value(id),
          title: title.trim(),
          priority: Value(priority),
          dueAt: Value(dueAt),
          projectId: Value(projectId),
          parentTaskId: Value(parentTaskId),
          recurrenceRule: Value(recurrenceRule),
        ));
    return id;
  }

  Future<void> update(String id,
      {required String title,
      required int priority,
      DateTime? dueAt,
      String? projectId}) {
    return (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        title: Value(title.trim()),
        priority: Value(priority),
        dueAt: Value<DateTime?>(dueAt),
        projectId: Value<String?>(projectId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// تعديل حقول محددة فقط (يُحدَّث updatedAt تلقائيًا).
  Future<void> updateFields(String id, TasksCompanion c) =>
      (_db.update(_db.tasks)..where((t) => t.id.equals(id)))
          .write(c.copyWith(updatedAt: Value(DateTime.now())));

  Future<void> softDelete(String id) =>
      (_db.update(_db.tasks)..where((t) => t.id.equals(id)))
          .write(TasksCompanion(deletedAt: Value(DateTime.now())));

  Future<void> restore(String id) =>
      (_db.update(_db.tasks)..where((t) => t.id.equals(id)))
          .write(const TasksCompanion(deletedAt: Value<DateTime?>(null)));

  // ---------- الإنجاز والتكرار ----------

  /// يبدّل حالة المهمة بين منجزة وغير منجزة (انظر [setCompleted]).
  Future<CompleteResult> toggle(Task t) => setCompleted(t.id, t.status != 'done');

  /// يُنجز المهمة أو يعيد فتحها.
  /// - لا تُنجز مهمة تعتمد على مهام غير منجزة (تُرجَع في [CompleteResult.blockers]).
  /// - إنجاز مهمة متكررة ينشئ نسختها التالية (مع مهامها الفرعية غير منجزة).
  Future<CompleteResult> setCompleted(String id, bool done) {
    return _db.transaction(() async {
      final t = await getById(id);
      if (t == null) return const CompleteResult([]);
      final now = DateTime.now();

      if (!done) {
        await (_db.update(_db.tasks)..where((x) => x.id.equals(id))).write(
          TasksCompanion(
            status: const Value('todo'),
            completedAt: const Value<DateTime?>(null),
            updatedAt: Value(now),
          ),
        );
        return const CompleteResult([]);
      }

      final blockers = (await dependenciesOf(id))
          .where((d) => d.status != 'done')
          .toList();
      if (blockers.isNotEmpty) return CompleteResult(blockers);

      await (_db.update(_db.tasks)..where((x) => x.id.equals(id))).write(
        TasksCompanion(
          status: const Value('done'),
          completedAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      final rule = t.recurrenceRule;
      if (rule != null && rule.isNotEmpty && t.status != 'done') {
        await _spawnNext(t, rule, now);
      }
      return const CompleteResult([]);
    });
  }

  Future<void> _spawnNext(Task t, String rule, DateTime now) async {
    final next = nextDueAfter(t.dueAt ?? now, rule, startOfDay(now));
    final newId = const Uuid().v4();
    await _db.into(_db.tasks).insert(TasksCompanion.insert(
          id: Value(newId),
          title: t.title,
          description: Value(t.description),
          priority: Value(t.priority),
          dueAt: Value(next),
          projectId: Value(t.projectId),
          recurrenceRule: Value(rule),
        ));
    final subs = await (_db.select(_db.tasks)
          ..where((s) => s.parentTaskId.equals(t.id) & s.deletedAt.isNull()))
        .get();
    for (final s in subs) {
      await _db.into(_db.tasks).insert(
          TasksCompanion.insert(title: s.title, parentTaskId: Value(newId)));
    }
  }

  // ---------- النقل بين الأيام ----------

  /// ينقل المهمة إلى [day] مع الحفاظ على وقتها إن كان لها وقت.
  Future<void> moveTo(String id, DateTime day) async {
    final t = await getById(id);
    if (t == null) return;
    final old = t.dueAt;
    await updateFields(
        id,
        TasksCompanion(
            dueAt: Value(DateTime(day.year, day.month, day.day,
                old?.hour ?? 0, old?.minute ?? 0))));
  }

  /// ينقل كل المهام المتأخرة غير المنجزة إلى اليوم، ويُرجع عددها.
  Future<int> moveOverdueToToday() => _db.transaction(() async {
        final today = startOfDay(DateTime.now());
        final rows = await (_db.select(_db.tasks)
              ..where((t) =>
                  t.deletedAt.isNull() &
                  t.status.equals('done').not() &
                  t.dueAt.isSmallerThanValue(today)))
            .get();
        for (final t in rows) {
          await moveTo(t.id, today);
        }
        return rows.length;
      });

  // ---------- الاعتماديات ----------

  /// المهام التي تعتمد عليها [taskId] (يجب إنجازها أولًا).
  Future<List<Task>> dependenciesOf(String taskId) {
    final q = _db.select(_db.tasks).join([
      innerJoin(_db.taskDeps, _db.taskDeps.dependsOnId.equalsExp(_db.tasks.id)),
    ])
      ..where(_db.taskDeps.taskId.equals(taskId) & _db.tasks.deletedAt.isNull());
    return q.map((r) => r.readTable(_db.tasks)).get();
  }

  Stream<List<Task>> watchDependencies(String taskId) {
    final q = _db.select(_db.tasks).join([
      innerJoin(_db.taskDeps, _db.taskDeps.dependsOnId.equalsExp(_db.tasks.id)),
    ])
      ..where(_db.taskDeps.taskId.equals(taskId) & _db.tasks.deletedAt.isNull())
      ..orderBy([OrderingTerm.asc(_db.tasks.title)]);
    return q.map((r) => r.readTable(_db.tasks)).watch();
  }

  /// يضيف اعتمادًا. يُرجع false إن كان ذاتيًا أو يصنع دورة (أ تعتمد على ب وب على أ).
  Future<bool> addDependency(String taskId, String dependsOnId) async {
    if (taskId == dependsOnId || await _reaches(dependsOnId, taskId)) return false;
    await _db.into(_db.taskDeps).insert(
        TaskDepsCompanion.insert(taskId: taskId, dependsOnId: dependsOnId),
        mode: InsertMode.insertOrIgnore);
    return true;
  }

  /// هل تصل [from] إلى [target] بتتبّع الاعتماديات؟
  Future<bool> _reaches(String from, String target) async {
    final seen = <String>{};
    final stack = [from];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      if (cur == target) return true;
      if (!seen.add(cur)) continue;
      final rows = await (_db.select(_db.taskDeps)
            ..where((d) => d.taskId.equals(cur)))
          .get();
      stack.addAll(rows.map((r) => r.dependsOnId));
    }
    return false;
  }

  Future<void> removeDependency(String taskId, String dependsOnId) =>
      (_db.delete(_db.taskDeps)
            ..where((d) => d.taskId.equals(taskId) & d.dependsOnId.equals(dependsOnId)))
          .go();

  /// مهام رئيسية غير منجزة لاختيارها كاعتماد.
  Future<List<Task>> openTasks({String? excludeId}) => (_db.select(_db.tasks)
        ..where((t) =>
            t.deletedAt.isNull() &
            t.parentTaskId.isNull() &
            t.status.equals('done').not() &
            (excludeId == null ? const Constant(true) : t.id.equals(excludeId).not()))
        ..orderBy([(t) => OrderingTerm.asc(t.title)]))
      .get();

  // ---------- الربط بالملاحظات ----------

  Stream<List<Note>> watchNotes(String taskId) {
    final q = _db.select(_db.notes).join([
      innerJoin(_db.taskNotes, _db.taskNotes.noteId.equalsExp(_db.notes.id)),
    ])
      ..where(_db.taskNotes.taskId.equals(taskId) & _db.notes.deletedAt.isNull())
      ..orderBy([OrderingTerm.asc(_db.notes.title)]);
    return q.map((r) => r.readTable(_db.notes)).watch();
  }

  Future<void> linkNote(String taskId, String noteId) => _db.into(_db.taskNotes).insert(
      TaskNotesCompanion.insert(taskId: taskId, noteId: noteId),
      mode: InsertMode.insertOrIgnore);

  Future<void> unlinkNote(String taskId, String noteId) => (_db.delete(_db.taskNotes)
        ..where((x) => x.taskId.equals(taskId) & x.noteId.equals(noteId)))
      .go();
}
