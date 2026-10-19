import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/core/recurrence.dart';

void main() {
  test('يومي وأسبوعي مع الحفاظ على الوقت', () {
    final d = DateTime(2099, 1, 1, 10, 30);
    expect(nextOccurrence(d, 'daily'), DateTime(2099, 1, 2, 10, 30));
    expect(nextOccurrence(d, 'weekly'), DateTime(2099, 1, 8, 10, 30));
  });

  test('الشهري يقصّ اليوم إلى آخر يوم في الشهر القصير', () {
    expect(nextOccurrence(DateTime(2099, 1, 31), 'monthly'), DateTime(2099, 2, 28));
    expect(nextOccurrence(DateTime(2096, 1, 31), 'monthly'), DateTime(2096, 2, 29)); // سنة كبيسة
    expect(nextOccurrence(DateTime(2099, 12, 15), 'monthly'), DateTime(2100, 1, 15));
  });

  test('الموعد التالي لا يقع في الماضي', () {
    final today = DateTime(2026, 10, 19);
    // مهمة يومية كان موعدها قبل أسبوع: التالي اليوم لا أمس
    expect(nextDueAfter(DateTime(2026, 10, 12), 'daily', today), DateTime(2026, 10, 19));
    // أسبوعية متأخرة: أول أسبوع لا يسبق اليوم
    expect(nextDueAfter(DateTime(2026, 9, 28), 'weekly', today), DateTime(2026, 10, 19));
    // موعد مستقبلي: خطوة واحدة فقط
    expect(nextDueAfter(DateTime(2099, 1, 1), 'weekly', today), DateTime(2099, 1, 8));
  });

  test('قاعدة غير معروفة لا تُدخل حلقة لانهائية', () {
    final d = DateTime(2020, 1, 1);
    expect(nextDueAfter(d, 'bogus', DateTime(2026, 1, 1)), d);
  });
}
