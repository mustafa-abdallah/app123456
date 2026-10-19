import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/database.dart';

/// تصدير كل البيانات إلى JSON واستيرادها (دمج دون حذف).
class BackupService {
  BackupService(this._db);
  final AppDatabase _db;

  static const appId = 'knowledge_app';
  static const formatVersion = 1;

  Future<List<Map<String, dynamic>>> _dump<T extends HasResultSet, D>(
          ResultSetImplementation<T, D> table, Map<String, dynamic> Function(D) toJson) async =>
      (await _db.select(table).get()).map(toJson).toList();

  /// يشمل المحذوفات المنطقية أيضًا ليكون الاسترجاع كاملًا.
  Future<String> exportJson() async {
    final tables = <String, List<Map<String, dynamic>>>{
      'folders': await _dump(_db.folders, (Folder r) => r.toJson()),
      'projects': await _dump(_db.projects, (Project r) => r.toJson()),
      'tags': await _dump(_db.tags, (Tag r) => r.toJson()),
      'notes': await _dump(_db.notes, (Note r) => r.toJson()),
      'noteTags': await _dump(_db.noteTags, (NoteTag r) => r.toJson()),
      'links': await _dump(_db.links, (Link r) => r.toJson()),
      'noteVersions': await _dump(_db.noteVersions, (NoteVersion r) => r.toJson()),
      'attachments': await _dump(_db.attachments, (Attachment r) => r.toJson()),
      'tasks': await _dump(_db.tasks, (Task r) => r.toJson()),
      'taskDeps': await _dump(_db.taskDeps, (TaskDep r) => r.toJson()),
      'habits': await _dump(_db.habits, (Habit r) => r.toJson()),
      'habitSchedules': await _dump(_db.habitSchedules, (HabitSchedule r) => r.toJson()),
      'habitLogs': await _dump(_db.habitLogs, (HabitLog r) => r.toJson()),
    };
    return jsonEncode({
      'app': appId,
      'version': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': tables,
    });
  }

  /// يدمج النسخة في القاعدة الحالية: السجل الموجود بالمعرّف نفسه يُحدَّث،
  /// وما عداه يبقى كما هو. العملية كلها في معاملة واحدة: إما تنجح كاملة أو لا يتغير شيء.
  /// تُرجع عدد السجلات المستوردة، وتُلقي [FormatException] برسالة عربية عند الخطأ.
  Future<int> importJson(String text) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(text.trim());
    } on FormatException {
      throw const FormatException('النص ليس نسخة احتياطية صالحة');
    }
    if (decoded is! Map<String, dynamic> || decoded['app'] != appId) {
      throw const FormatException('هذه ليست نسخة احتياطية من هذا التطبيق');
    }
    final version = decoded['version'];
    if (version is! int || version > formatVersion) {
      throw const FormatException('إصدار النسخة غير مدعوم، حدّث التطبيق أولًا');
    }
    final tables = decoded['tables'];
    if (tables is! Map) {
      throw const FormatException('النسخة تالفة: لا توجد جداول');
    }

    List<Map<String, dynamic>> rows(String name) {
      final l = tables[name];
      if (l == null) return const [];
      if (l is! List) throw FormatException('النسخة تالفة: الجدول $name');
      return [for (final e in l) Map<String, dynamic>.from(e as Map)];
    }

    var total = 0;
    try {
      await _db.transaction(() async {
        // الأب قد يأتي بعد الابن في الملف؛ نؤجل فحص المفاتيح الأجنبية لنهاية المعاملة.
        await _db.customStatement('PRAGMA defer_foreign_keys = ON');

        // toCompanion(false): القيم الفارغة (مثل deletedAt) تُكتب فعلًا فتُلغي أثر الحذف،
        // بدل أن تُتجاهل فيبقى السجل المحذوف مخفيًا بعد الاستيراد.
        Future<void> put<T extends Table, D>(TableInfo<T, D> table, String name,
            Insertable<D> Function(Map<String, dynamic>) from) async {
          for (final r in rows(name)) {
            await _db.into(table).insertOnConflictUpdate(from(r));
            total++;
          }
        }

        await put(_db.folders, 'folders', (j) => Folder.fromJson(j).toCompanion(false));
        await put(_db.projects, 'projects', (j) => Project.fromJson(j).toCompanion(false));
        await put(_db.tags, 'tags', (j) => Tag.fromJson(j).toCompanion(false));
        await put(_db.notes, 'notes', (j) => Note.fromJson(j).toCompanion(false));
        await put(_db.noteTags, 'noteTags', (j) => NoteTag.fromJson(j).toCompanion(false));
        await put(_db.links, 'links', (j) => Link.fromJson(j).toCompanion(false));
        await put(_db.noteVersions, 'noteVersions', (j) => NoteVersion.fromJson(j).toCompanion(false));
        await put(_db.attachments, 'attachments', (j) => Attachment.fromJson(j).toCompanion(false));
        await put(_db.tasks, 'tasks', (j) => Task.fromJson(j).toCompanion(false));
        await put(_db.taskDeps, 'taskDeps', (j) => TaskDep.fromJson(j).toCompanion(false));
        await put(_db.habits, 'habits', (j) => Habit.fromJson(j).toCompanion(false));
        await put(_db.habitSchedules, 'habitSchedules', (j) => HabitSchedule.fromJson(j).toCompanion(false));
        await put(_db.habitLogs, 'habitLogs', (j) => HabitLog.fromJson(j).toCompanion(false));
      });
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('تعذّر الاستيراد ولم يتغيّر شيء: $e');
    }
    return total;
  }
}
