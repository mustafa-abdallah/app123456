import 'package:drift/drift.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  Folders, Notes, NoteVersions, Tags, NoteTags, Links, Attachments,
  Projects, Tasks, TaskDeps, Habits, HabitSchedules, HabitLogs,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// ارفع الرقم مع كل تغيير في المخطط، وأضف خطوة ترحيل في onUpgrade.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createSearchIndex();
        },
        onUpgrade: (m, from, to) async {
          // مثال للمستقبل:
          // if (from < 2) { await m.addColumn(notes, notes.someColumn); }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _createSearchIndex() async {
    await customStatement('''
      CREATE VIRTUAL TABLE notes_fts USING fts5(
        title, body_md,
        content='notes', content_rowid='rowid',
        tokenize='unicode61'
      )''');
    await customStatement('''
      CREATE TRIGGER notes_ai AFTER INSERT ON notes BEGIN
        INSERT INTO notes_fts(rowid, title, body_md)
        VALUES (new.rowid, new.title, new.body_md);
      END''');
    await customStatement('''
      CREATE TRIGGER notes_ad AFTER DELETE ON notes BEGIN
        INSERT INTO notes_fts(notes_fts, rowid, title, body_md)
        VALUES ('delete', old.rowid, old.title, old.body_md);
      END''');
    await customStatement('''
      CREATE TRIGGER notes_au AFTER UPDATE ON notes BEGIN
        INSERT INTO notes_fts(notes_fts, rowid, title, body_md)
        VALUES ('delete', old.rowid, old.title, old.body_md);
        INSERT INTO notes_fts(rowid, title, body_md)
        VALUES (new.rowid, new.title, new.body_md);
      END''');
  }

  /// بحث نصي كامل (نتائج مرتبة حسب الصلة).
  Future<List<Note>> searchNotes(String query) {
    final q = query.trim().replaceAll('"', '');
    if (q.isEmpty) return Future.value([]);
    return customSelect(
      '''SELECT n.* FROM notes n
         JOIN notes_fts f ON f.rowid = n.rowid
         WHERE notes_fts MATCH ? AND n.deleted_at IS NULL
         ORDER BY rank''',
      variables: [Variable.withString('"$q"*')],
      readsFrom: {notes},
    ).map((row) => notes.map(row.data)).get();
  }
}
