import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/wiki_links.dart';
import '../database/database.dart';

/// مرشّح قائمة الملاحظات: الكل، مجلد، وسم، أو المحذوفات.
class NotesFilter {
  const NotesFilter({this.folderId, this.tagId, this.trash = false, this.label = ''});
  final String? folderId;
  final String? tagId;
  final bool trash;
  final String label;

  bool get isDefault => folderId == null && tagId == null && !trash;

  @override
  bool operator ==(Object other) =>
      other is NotesFilter &&
      other.folderId == folderId &&
      other.tagId == tagId &&
      other.trash == trash &&
      other.label == label;

  @override
  int get hashCode => Object.hash(folderId, tagId, trash, label);
}

class TagCount {
  const TagCount(this.id, this.name, this.count);
  final String id;
  final String name;
  final int count;
}

/// المصدر الوحيد لبيانات الملاحظات والوسوم والروابط.
class NotesRepository {
  NotesRepository(this._db);
  final AppDatabase _db;

  /// أقل فاصل بين نسختين في سجل التعديلات أثناء الكتابة المستمرة.
  static const versionGap = Duration(minutes: 5);

  // ---------- القراءة ----------

  Stream<List<Note>> watch(NotesFilter f) {
    final q = _db.select(_db.notes);
    if (f.trash) {
      q.where((n) => n.deletedAt.isNotNull());
    } else {
      q.where((n) => n.deletedAt.isNull());
    }
    if (f.folderId != null) {
      q.where((n) => n.folderId.equals(f.folderId!));
    }
    if (f.tagId != null) {
      final sub = _db.selectOnly(_db.noteTags)
        ..addColumns([_db.noteTags.noteId])
        ..where(_db.noteTags.tagId.equals(f.tagId!));
      q.where((n) => n.id.isInQuery(sub));
    }
    q.orderBy([(n) => OrderingTerm.desc(n.updatedAt)]);
    return q.watch();
  }

  Future<List<Note>> search(String query) => _db.searchNotes(query);

  Future<Note?> getById(String id) =>
      (_db.select(_db.notes)..where((n) => n.id.equals(id))).getSingleOrNull();

  Future<Note?> findByTitle(String title) => (_db.select(_db.notes)
        ..where((n) => n.deletedAt.isNull() & n.title.equals(title.trim()))
        ..limit(1))
      .getSingleOrNull();

  // ---------- الإنشاء والحفظ ----------

  Future<String> create({String title = '', String? folderId}) async {
    final id = const Uuid().v4();
    await _db.into(_db.notes).insert(NotesCompanion.insert(
        id: Value(id), title: Value(title), folderId: Value(folderId)));
    return id;
  }

  /// يحفظ الملاحظة ويضيف نسخة في السجل عند الحاجة، كله في معاملة واحدة.
  Future<void> save(String id, {required String title, required String body}) {
    return _db.transaction(() async {
      final now = DateTime.now();
      await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
        NotesCompanion(
            title: Value(title), bodyMd: Value(body), updatedAt: Value(now)),
      );
      final last = await (_db.select(_db.noteVersions)
            ..where((v) => v.noteId.equals(id))
            ..orderBy([(v) => OrderingTerm.desc(v.createdAt)])
            ..limit(1))
          .getSingleOrNull();
      final due = last == null ||
          (last.bodyMd != body && now.difference(last.createdAt) > versionGap);
      if (due) {
        await _db.into(_db.noteVersions).insert(
            NoteVersionsCompanion.insert(noteId: id, title: title, bodyMd: body));
      }
    });
  }

  /// نسخة فورية في السجل (تُستخدم قبل استرجاع نسخة قديمة).
  Future<void> snapshot(String id,
      {required String title, required String body}) async {
    await _db.into(_db.noteVersions).insert(
        NoteVersionsCompanion.insert(noteId: id, title: title, bodyMd: body));
  }

  Future<List<NoteVersion>> versions(String noteId) => (_db.select(_db.noteVersions)
        ..where((v) => v.noteId.equals(noteId))
        ..orderBy([(v) => OrderingTerm.desc(v.createdAt)]))
      .get();

  Future<void> softDelete(String id) =>
      (_db.update(_db.notes)..where((n) => n.id.equals(id)))
          .write(NotesCompanion(deletedAt: Value(DateTime.now())));

  Future<void> restore(String id) =>
      (_db.update(_db.notes)..where((n) => n.id.equals(id)))
          .write(const NotesCompanion(deletedAt: Value<DateTime?>(null)));

  /// يحذف الملاحظة نهائيًا فقط إذا كانت فارغة تمامًا (فتحها المستخدم ثم خرج).
  Future<void> deleteIfEmpty(String id) => (_db.delete(_db.notes)
        ..where((n) =>
            n.id.equals(id) & n.title.equals('') & n.bodyMd.equals('')))
      .go();

  Future<void> moveToFolder(String noteId, String? folderId) =>
      (_db.update(_db.notes)..where((n) => n.id.equals(noteId)))
          .write(NotesCompanion(folderId: Value(folderId)));

  // ---------- الروابط الداخلية ----------

  /// الملاحظات التي تشير إلى هذه الملاحظة بعنوانها. تُحسب عند الطلب فلا تتقادم.
  Future<List<Note>> backlinks(String noteId) async {
    final me = await getById(noteId);
    final title = me?.title.trim() ?? '';
    if (title.isEmpty) return [];
    final rows = await (_db.select(_db.notes)
          ..where((n) =>
              n.deletedAt.isNull() &
              n.id.equals(noteId).not() &
              n.bodyMd.like('%[[%'))
          ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]))
        .get();
    return rows.where((n) => extractLinkTitles(n.bodyMd).contains(title)).toList();
  }

  // ---------- الوسوم ----------

  Future<List<Tag>> tagsFor(String noteId) {
    final q = _db.select(_db.tags).join([
      innerJoin(_db.noteTags, _db.noteTags.tagId.equalsExp(_db.tags.id)),
    ])
      ..where(_db.noteTags.noteId.equals(noteId) & _db.tags.deletedAt.isNull())
      ..orderBy([OrderingTerm.asc(_db.tags.name)]);
    return q.map((r) => r.readTable(_db.tags)).get();
  }

  Future<void> addTag(String noteId, String rawName) async {
    final name = rawName.trim().replaceFirst(RegExp(r'^#+'), '').trim();
    if (name.isEmpty) return;
    await _db.transaction(() async {
      final existing = await (_db.select(_db.tags)..where((t) => t.name.equals(name)))
          .getSingleOrNull();
      final id = existing?.id ?? const Uuid().v4();
      if (existing == null) {
        await _db.into(_db.tags).insert(TagsCompanion.insert(id: Value(id), name: name));
      }
      await attachTag(noteId, id);
    });
  }

  Future<void> attachTag(String noteId, String tagId) =>
      _db.into(_db.noteTags).insert(
          NoteTagsCompanion.insert(noteId: noteId, tagId: tagId),
          mode: InsertMode.insertOrIgnore);

  Future<void> removeTag(String noteId, String tagId) => (_db.delete(_db.noteTags)
        ..where((x) => x.noteId.equals(noteId) & x.tagId.equals(tagId)))
      .go();

  Future<List<TagCount>> tagsWithCounts() async {
    final rows = await _db.customSelect('''
      SELECT t.id AS id, t.name AS name, COUNT(n.id) AS c
      FROM tags t
      LEFT JOIN note_tags nt ON nt.tag_id = t.id
      LEFT JOIN notes n ON n.id = nt.note_id AND n.deleted_at IS NULL
      WHERE t.deleted_at IS NULL
      GROUP BY t.id
      ORDER BY t.name''').get();
    return rows
        .map((r) => TagCount(r.read<String>('id'), r.read<String>('name'), r.read<int>('c')))
        .toList();
  }
}
