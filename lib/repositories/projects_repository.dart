import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';

/// التصنيفات (مشاريع) تُستخدم لتجميع المهام.
class ProjectsRepository {
  ProjectsRepository(this._db);
  final AppDatabase _db;

  Stream<List<Project>> watchActive() => (_db.select(_db.projects)
        ..where((p) => p.deletedAt.isNull() & p.archivedAt.isNull())
        ..orderBy([(p) => OrderingTerm.asc(p.name)]))
      .watch();

  Future<String> create(String name) async {
    final id = const Uuid().v4();
    await _db
        .into(_db.projects)
        .insert(ProjectsCompanion.insert(id: Value(id), name: name.trim()));
    return id;
  }

  Future<void> rename(String id, String name) =>
      (_db.update(_db.projects)..where((p) => p.id.equals(id))).write(
          ProjectsCompanion(name: Value(name.trim()), updatedAt: Value(DateTime.now())));

  /// حذف منطقي؛ مهام التصنيف تبقى دون تصنيف ولا تختفي.
  Future<void> delete(String id) => _db.transaction(() async {
        await (_db.update(_db.tasks)..where((t) => t.projectId.equals(id)))
            .write(const TasksCompanion(projectId: Value<String?>(null)));
        await (_db.update(_db.projects)..where((p) => p.id.equals(id)))
            .write(ProjectsCompanion(deletedAt: Value(DateTime.now())));
      });
}
