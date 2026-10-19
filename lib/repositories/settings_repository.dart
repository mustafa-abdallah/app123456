import 'package:drift/drift.dart';

import '../database/database.dart';

/// إعدادات التطبيق (مفتاح/قيمة) داخل قاعدة البيانات نفسها.
class SettingsRepository {
  SettingsRepository(this._db);
  final AppDatabase _db;

  /// المفاتيح التي تبدأ بهذه البادئة خاصة بالجهاز ولا تدخل في النسخ الاحتياطي.
  static const localPrefix = 'backup.';
  static const lastExportKey = 'backup.lastExportAt';

  Future<String?> get(String key) async {
    final r = await (_db.select(_db.appSettings)
          ..where((s) => s.settingKey.equals(key)))
        .getSingleOrNull();
    return r?.settingValue;
  }

  Future<void> set(String key, String value) =>
      _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
              settingKey: key,
              settingValue: value,
              updatedAt: Value(DateTime.now())));

  Future<void> remove(String key) =>
      (_db.delete(_db.appSettings)..where((s) => s.settingKey.equals(key))).go();

  Stream<String?> watch(String key) => (_db.select(_db.appSettings)
        ..where((s) => s.settingKey.equals(key)))
      .watchSingleOrNull()
      .map((r) => r?.settingValue);

  Stream<DateTime?> watchLastExport() =>
      watch(lastExportKey).map((v) => v == null ? null : DateTime.tryParse(v));

  Future<void> markExported([DateTime? at]) =>
      set(lastExportKey, (at ?? DateTime.now()).toIso8601String());
}
