import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/core/format.dart';
import 'package:knowledge_app/core/streak.dart';

void main() {
  final today = DateTime(2026, 10, 19); // اثنين
  Set<String> days(List<int> offsets) => {
        for (final o in offsets)
          formatDate(DateTime(today.year, today.month, today.day - o))
      };

  test('تسلسل متصل يشمل اليوم', () {
    expect(currentStreak(days([0, 1, 2]), today), 3);
  });

  test('عدم الإنجاز اليوم لا يقطع التسلسل', () {
    expect(currentStreak(days([1, 2, 3]), today), 3);
  });

  test('الانقطاع يوقف العدّ', () {
    expect(currentStreak(days([0, 1, 3, 4]), today), 2);
  });

  test('لا سجل = صفر', () {
    expect(currentStreak({}, today), 0);
  });

  test('الأيام غير المجدولة لا تقطع التسلسل', () {
    // الجدول: الاثنين فقط (البت 0). الاثنين اليوم والاثنين السابق = 7 أيام قبل.
    expect(currentStreak(days([0, 7, 14]), today, daysMask: 1), 3);
  });
}
