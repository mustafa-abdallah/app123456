import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/core/format.dart';
import 'package:knowledge_app/core/habit_stats.dart';

void main() {
  final today = DateTime(2026, 10, 19); // اثنين
  DateTime ago(int o) => DateTime(today.year, today.month, today.day - o);
  Set<String> days(List<int> offsets) => {for (final o in offsets) formatDate(ago(o))};

  test('أفضل تسلسل والتسلسل الحالي', () {
    final s = computeHabitStats(days([0, 1, 2, 10, 11, 12, 13, 14]), today,
        since: ago(20));
    expect(s.currentStreak, 3);
    expect(s.bestStreak, 5);
    expect(s.doneInWindow, 8);
  });

  test('نسبة الالتزام تُحسب من بداية العادة', () {
    final s = computeHabitStats(days([0, 1, 2, 10, 11, 12, 13, 14]), today,
        since: ago(20));
    expect(s.rate30, closeTo(8 / 21, 1e-9));
    expect(s.rateAll, closeTo(8 / 21, 1e-9));
  });

  test('توزيع الإنجاز على أيام الأسبوع', () {
    final s = computeHabitStats(days([0, 1, 2, 10, 11, 12, 13, 14]), today,
        since: ago(20));
    expect(s.weekdayDone, [2, 1, 1, 1, 1, 1, 1]);
  });

  test('الأيام غير المجدولة لا تُحسب في النسبة', () {
    // الاثنين فقط: 0 و7 و14 كلها منجزة.
    final s = computeHabitStats(days([0, 7, 14]), today, daysMask: 1, since: ago(14));
    expect(s.rateAll, 1.0);
    expect(s.bestStreak, 3);
  });

  test('بلا سجل: كل القيم صفر دون أخطاء قسمة', () {
    final s = computeHabitStats({}, today, since: today);
    expect(s.currentStreak, 0);
    expect(s.bestStreak, 0);
    expect(s.rate30, 0);
    expect(s.weekdayDone, List.filled(7, 0));
  });
}
