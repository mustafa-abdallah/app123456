import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';

enum TaskView { active, done }

/// المصدر الوحيد لبيانات المهام.
class TasksRepository {
  TasksRepository(this._db);
  final AppDatabase _db;

  static const priorityLabels = ['عادية', 'متوسطة', 'عالية'];

  Stream<List<Task>> watch(TaskView view) {
    final q = _db.select(_db.tasks)..where((t) => t.deletedAt.isNull());
    if (view == TaskView.done) {
      q
        ..where((t) => t.status.equals('done'))
        ..orderBy([(t) => OrderingTerm.desc(t.completedAt)]);
    } else {
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

  Future<String> create(String title, {int priority = 0, DateTime? dueAt}) async {
    final id = const Uuid().v4();
    await _db.into(_db.tasks).insert(TasksCompanion.insert(
          id: Value(id),
          title: title.trim(),
          priority: Value(priority),
          dueAt: Value(dueAt),
        ));
    return id;
  }

  Future<void> update(String id,
      {required String title, required int priority, DateTime? dueAt}) {
    return (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        title: Value(title.trim()),
        priority: Value(priority),
        dueAt: Value<DateTime?>(dueAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// يبدّل حالة المهمة بين منجزة وغير منجزة.
  Future<void> toggle(Task t) {
    final nowDone = t.status != 'done';
    final now = DateTime.now();
    return (_db.update(_db.tasks)..where((x) => x.id.equals(t.id))).write(
      TasksCompanion(
        status: Value(nowDone ? 'done' : 'todo'),
        completedAt: Value<DateTime?>(nowDone ? now : null),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> softDelete(String id) =>
      (_db.update(_db.tasks)..where((t) => t.id.equals(id)))
          .write(TasksCompanion(deletedAt: Value(DateTime.now())));

  Future<void> restore(String id) =>
      (_db.update(_db.tasks)..where((t) => t.id.equals(id)))
          .write(const TasksCompanion(deletedAt: Value<DateTime?>(null)));
}
