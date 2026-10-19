import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../database/database.dart';
import '../repositories/settings_repository.dart';

/// ملخص نسخة احتياطية بعد فحصها (قبل أي تغيير في البيانات).
class BackupInfo {
  const BackupInfo({
    required this.version,
    required this.exportedAt,
    required this.counts,
    required this.verified,
  });

  final int version;
  final DateTime? exportedAt;

  /// عدد السجلات في كل جدول.
  final Map<String, int> counts;

  /// true = تحقّقنا من المجموع الاختباري. false = نسخة قديمة بلا مجموع اختباري.
  final bool verified;

  int get total => counts.values.fold(0, (a, b) => a + b);
}

typedef _Parsed = ({
  int version,
  DateTime? exportedAt,
  Map<String, dynamic> tables,
  Map<String, int> counts,
  bool verified,
});

/// تصدير كل البيانات إلى JSON واستيرادها (دمج أو استبدال كامل).
///
/// الإصدار 2 يضيف: أعداد الجداول + مجموع اختباري SHA-256، لاكتشاف أي تلف
/// أو نقص أو تعديل قبل الاستعادة. الإصدار 1 (بلا مجموع اختباري) ما زال مقبولًا.
class BackupService {
  BackupService(this._db);
  final AppDatabase _db;

  static const appId = 'knowledge_app';
  static const formatVersion = 2;

  Future<List<Map<String, dynamic>>> _dump<T extends HasResultSet, D>(
          ResultSetImplementation<T, D> table, Map<String, dynamic> Function(D) toJson) async =>
      (await _db.select(table).get()).map(toJson).toList();

  static String _checksum(Object tables) =>
      sha256.convert(utf8.encode(jsonEncode(tables))).toString();

  /// يشمل المحذوفات المنطقية أيضًا ليكون الاسترجاع كاملًا.
  Future<String> exportJson() async {
    final settings = (await _db.select(_db.appSettings).get())
        .where((s) => !s.settingKey.startsWith(SettingsRepository.localPrefix))
        .map((s) => s.toJson())
        .toList();
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
      'taskNotes': await _dump(_db.taskNotes, (TaskNote r) => r.toJson()),
      'habits': await _dump(_db.habits, (Habit r) => r.toJson()),
      'habitSchedules': await _dump(_db.habitSchedules, (HabitSchedule r) => r.toJson()),
      'habitLogs': await _dump(_db.habitLogs, (HabitLog r) => r.toJson()),
      'appSettings': settings,
    };
    return jsonEncode({
      'app': appId,
      'version': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'counts': {for (final e in tables.entries) e.key: e.value.length},
      'checksum': _checksum(tables),
      'tables': tables,
    });
  }

  /// يقرأ النسخة ويتحقق من سلامتها دون أي كتابة. يُلقي [FormatException] برسالة عربية.
  _Parsed _parse(String text) {
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
    final rawTables = decoded['tables'];
    if (rawTables is! Map) {
      throw const FormatException('النسخة تالفة: لا توجد جداول');
    }
    final tables = Map<String, dynamic>.from(rawTables);
    final counts = <String, int>{};
    for (final e in tables.entries) {
      final v = e.value;
      if (v is! List) throw FormatException('النسخة تالفة: الجدول ${e.key}');
      counts[e.key] = v.length;
    }

    final expected = decoded['counts'];
    if (expected is Map) {
      for (final e in expected.entries) {
        if ((counts[e.key] ?? 0) != e.value) {
          throw FormatException('النسخة ناقصة أو معدّلة: عدد سجلات ${e.key} لا يطابق');
        }
      }
    }

    var verified = false;
    final checksum = decoded['checksum'];
    if (checksum != null) {
      if (checksum is! String || checksum != _checksum(tables)) {
        throw const FormatException('النسخة تالفة أو عُدّلت: المجموع الاختباري لا يطابق');
      }
      verified = true;
    }

    final at = decoded['exportedAt'];
    return (
      version: version,
      exportedAt: at is String ? DateTime.tryParse(at) : null,
      tables: tables,
      counts: counts,
      verified: verified,
    );
  }

  /// فحص النسخة وعرض ملخصها قبل الاستعادة (لا يغيّر شيئًا).
  BackupInfo inspect(String text) {
    final p = _parse(text);
    return BackupInfo(
        version: p.version,
        exportedAt: p.exportedAt,
        counts: p.counts,
        verified: p.verified);
  }

  /// يستعيد النسخة في القاعدة الحالية.
  ///
  /// - الافتراضي (دمج): السجل الموجود بالمعرّف نفسه يُحدَّث، وما عداه يبقى.
  /// - [replace] = true: يُمسح كل شيء ثم تُستعاد النسخة (عدا بيانات الجهاز backup.*).
  ///
  /// العملية كلها في معاملة واحدة: إما تنجح كاملة أو لا يتغير شيء (حتى المسح).
  /// تُرجع عدد السجلات المستوردة، وتُلقي [FormatException] برسالة عربية عند الخطأ.
  Future<int> importJson(String text, {bool replace = false}) async {
    final tables = _parse(text).tables;

    List<Map<String, dynamic>> rows(String name) {
      final l = tables[name];
      if (l == null) return const [];
      return [for (final e in (l as List)) Map<String, dynamic>.from(e as Map)];
    }

    var total = 0;
    try {
      await _db.transaction(() async {
        // الأب قد يأتي بعد الابن في الملف؛ نؤجل فحص المفاتيح الأجنبية لنهاية المعاملة.
        await _db.customStatement('PRAGMA defer_foreign_keys = ON');

        if (replace) await _wipe();

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
        await put(_db.taskNotes, 'taskNotes', (j) => TaskNote.fromJson(j).toCompanion(false));
        await put(_db.habits, 'habits', (j) => Habit.fromJson(j).toCompanion(false));
        await put(_db.habitSchedules, 'habitSchedules', (j) => HabitSchedule.fromJson(j).toCompanion(false));
        await put(_db.habitLogs, 'habitLogs', (j) => HabitLog.fromJson(j).toCompanion(false));
        await put(_db.appSettings, 'appSettings', (j) => AppSetting.fromJson(j).toCompanion(false));
      });
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('تعذّر الاستيراد ولم يتغيّر شيء: $e');
    }
    return total;
  }

  /// يمسح كل الجداول (داخل معاملة الاستيراد، فيُتراجع عنه إن فشل شيء).
  Future<void> _wipe() async {
    await _db.delete(_db.noteTags).go();
    await _db.delete(_db.links).go();
    await _db.delete(_db.noteVersions).go();
    await _db.delete(_db.attachments).go();
    await _db.delete(_db.taskDeps).go();
    await _db.delete(_db.taskNotes).go();
    await _db.delete(_db.habitLogs).go();
    await _db.delete(_db.habitSchedules).go();
    await _db.delete(_db.tasks).go();
    await _db.delete(_db.habits).go();
    await _db.delete(_db.notes).go();
    await _db.delete(_db.tags).go();
    await _db.delete(_db.projects).go();
    await _db.delete(_db.folders).go();
    await (_db.delete(_db.appSettings)
          ..where((s) => s.settingKey.like('${SettingsRepository.localPrefix}%').not()))
        .go();
  }
}
