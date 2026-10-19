import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/core/habit_stats.dart';
import 'package:knowledge_app/core/streak.dart';

void main() {
  // 2026-10-19 الاثنين
  final today = DateTime(2026, 10, 19);

  test('الإنجاز الجزئي يُحتسب جزئيًا في النسبة ولا يستمر به التسلسل', () {
    final s = computeHabitStats({'2026-10-18'}, today,
        since: DateTime(2026, 10, 18), partial: {'2026-10-19': 0.5});
    expect(s.rateAll, closeTo(0.75, 1e-9)); // (1 + 0.5) / 2
    expect(s.currentStreak, 1); // اليوم جزئي فلا يمدّ التسلسل
  });

  test('يوم الإجازة محايد: لا يقطع التسلسل ولا يدخل في النسبة', () {
    final done = {'2026-10-17', '2026-10-19'};
    final withExcuse = computeHabitStats(done, today,
        since: DateTime(2026, 10, 17), excused: {'2026-10-18'});
    expect(withExcuse.currentStreak, 2);
    expect(withExcuse.rateAll, 1.0);

    final without = computeHabitStats(done, today, since: DateTime(2026, 10, 17));
    expect(without.currentStreak, 1);
    expect(without.rateAll, closeTo(2 / 3, 1e-9));
  });

  test('الجدول التاريخي يتجاوز الأيام غير المستهدفة', () {
    // لا جمعة ولا سبت: الخميس 15 منجز، الأحد 18 منجز
    bool sched(DateTime d) => d.weekday != DateTime.friday && d.weekday != DateTime.saturday;
    final done = {'2026-10-15', '2026-10-18'};
    expect(currentStreak(done, DateTime(2026, 10, 18), scheduledOn: sched), 2);
    final s = computeHabitStats(done, DateTime(2026, 10, 18),
        since: DateTime(2026, 10, 15), scheduledOn: sched);
    expect(s.currentStreak, 2);
    expect(s.rateAll, 1.0); // الجمعة والسبت خارج الحساب
  });

  test('السلوك القديم بلا معاملات جديدة لم يتغير', () {
    final s = computeHabitStats({'2026-10-18', '2026-10-19'}, today,
        since: DateTime(2026, 10, 17));
    expect(s.currentStreak, 2);
    expect(s.bestStreak, 2);
    expect(s.rateAll, closeTo(2 / 3, 1e-9));
  });
}
