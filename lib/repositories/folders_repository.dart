import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';

class FoldersRepository {
  FoldersRepository(this._db);
  final AppDatabase _db;

  Stream<List<Folder>> watchChildren(String? parentId) {
    final q = _db.select(_db.folders)
      ..where((f) =>
          f.deletedAt.isNull() &
          (parentId == null ? f.parentId.isNull() : f.parentId.equals(parentId)))
      ..orderBy([(f) => OrderingTerm.asc(f.name)]);
    return q.watch();
  }

  Future<Folder?> getById(String id) =>
      (_db.select(_db.folders)..where((f) => f.id.equals(id))).getSingleOrNull();

  Future<String> create(String name, {String? parentId}) async {
    final id = const Uuid().v4();
    await _db.into(_db.folders).insert(FoldersCompanion.insert(
        id: Value(id), name: name.trim(), parentId: Value(parentId)));
    return id;
  }

  Future<void> rename(String id, String name) =>
      (_db.update(_db.folders)..where((f) => f.id.equals(id))).write(
          FoldersCompanion(name: Value(name.trim()), updatedAt: Value(DateTime.now())));

  /// حذف منطقي؛ محتويات المجلد (ملاحظات ومجلدات فرعية) تنتقل إلى المجلد الأعلى.
  Future<void> delete(String id) => _db.transaction(() async {
        final f = await getById(id);
        if (f == null) return;
        final parent = f.parentId;
        await (_db.update(_db.notes)..where((n) => n.folderId.equals(id)))
            .write(NotesCompanion(folderId: Value(parent)));
        await (_db.update(_db.folders)..where((x) => x.parentId.equals(id)))
            .write(FoldersCompanion(parentId: Value(parent)));
        await (_db.update(_db.folders)..where((x) => x.id.equals(id)))
            .write(FoldersCompanion(deletedAt: Value(DateTime.now())));
      });

  /// كل المجلدات مع مسارها الكامل (مثل: أ / ب) لاستخدامها في نافذة النقل.
  Future<List<({Folder folder, String path})>> allWithPath() async {
    final all = await (_db.select(_db.folders)..where((f) => f.deletedAt.isNull())).get();
    final byId = {for (final f in all) f.id: f};
    String pathOf(Folder f) {
      final parts = <String>[];
      Folder? cur = f;
      var guard = 0;
      while (cur != null && guard++ < 50) {
        parts.insert(0, cur.name);
        cur = cur.parentId == null ? null : byId[cur.parentId];
      }
      return parts.join(' / ');
    }

    final out = [for (final f in all) (folder: f, path: pathOf(f))];
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }
}
