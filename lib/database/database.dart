import 'package:drift/drift.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  Folders, Notes, NoteVersions, Tags, NoteTags, Links, Attachments,
  Projects, Tasks, TaskDeps, Habits, HabitSchedules, HabitLogs, AppSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// سجل الإصدارات:
  ///  1 — المخطط الأول.
  ///  2 — إضافة جدول app_settings (إعدادات وتاريخ آخر نسخة احتياطية).
  ///
  /// عند أي تغيير في الجداول: ارفع الرقم، وأضف خطوة `if (from < N)` أدناه
  /// (createTable / addColumn ...)، وأضف اختبار ترحيل في test/database/migration_test.dart.
  /// لا تحذف قاعدة البيانات ولا تعد إنشاءها أبدًا.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createSearchIndex();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(appSettings);
          }
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

  /// فحص سلامة ملف قاعدة البيانات؛ يُرجع "ok" إن كان سليمًا.
  Future<String> integrityCheck() async {
    final rows = await customSelect('PRAGMA integrity_check').get();
    return rows.map((r) => r.read<String>('integrity_check')).join('\n');
  }

  /// إعادة بناء فهرس البحث من الملاحظات (إصلاح إن تلف الفهرس).
  Future<void> rebuildSearchIndex() =>
      customStatement("INSERT INTO notes_fts(notes_fts) VALUES('rebuild')");

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
