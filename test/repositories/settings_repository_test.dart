import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/database/database.dart';
import 'package:knowledge_app/repositories/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SettingsRepository(db);
  });
  tearDown(() => db.close());

  test('حفظ وقراءة وتحديث وحذف مفتاح', () async {
    expect(await repo.get('x'), isNull);
    await repo.set('x', '1');
    await repo.set('x', '2');
    expect(await repo.get('x'), '2');
    await repo.remove('x');
    expect(await repo.get('x'), isNull);
  });

  test('تاريخ آخر نسخة احتياطية يُحفظ ويُبثّ', () async {
    expect(await repo.watchLastExport().first, isNull);
    final at = DateTime(2026, 10, 18, 21, 30);
    await repo.markExported(at);
    expect((await repo.watchLastExport().first)!.millisecondsSinceEpoch,
        at.millisecondsSinceEpoch);
  });
}
