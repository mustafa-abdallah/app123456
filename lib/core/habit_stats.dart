import 'format.dart';
import 'streak.dart';

/// إحصاءات عادة واحدة، تُحسب من تواريخ الإنجاز فقط (دالة نقية قابلة للاختبار).
class HabitStats {
  const HabitStats({
    required this.currentStreak,
    required this.bestStreak,
    required this.doneInWindow,
    required this.rate30,
    required this.rateAll,
    required this.weekdayDone,
  });

  final int currentStreak;
  final int bestStreak;

  /// عدد أيام الإنجاز داخل النافذة المحسوبة.
  final int doneInWindow;

  /// نسبة الالتزام (0..1) في آخر 30 يومًا من الأيام المجدولة.
  final double rate30;

  /// نسبة الالتزام (0..1) منذ بداية العادة.
  final double rateAll;

  /// عدد مرات الإنجاز لكل يوم أسبوع، الفهرس = weekday - 1 (الاثنين أولًا).
  final List<int> weekdayDone;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// [since]: بداية العادة (تاريخ الإنشاء). إن وُجد إنجاز أقدم منه نبدأ منه.
/// [windowDays]: أقصى مدة رجوع إلى الوراء (تطابق نافذة التحميل).
HabitStats computeHabitStats(
  Set<String> done,
  DateTime today, {
  int daysMask = 127,
  DateTime? since,
  int windowDays = 365,
}) {
  final end = _dateOnly(today);
  final windowStart = DateTime(end.year, end.month, end.day - (windowDays - 1));

  var start = since == null ? windowStart : _dateOnly(since);
  for (final s in done) {
    final d = DateTime.tryParse(s);
    if (d != null && _dateOnly(d).isBefore(start)) start = _dateOnly(d);
  }
  if (start.isBefore(windowStart)) start = windowStart;
  if (start.isAfter(end)) start = end;

  final start30 = DateTime(end.year, end.month, end.day - 29);
  bool scheduled(DateTime d) => daysMask & (1 << (d.weekday - 1)) != 0;

  var best = 0, run = 0, doneCount = 0;
  var sched30 = 0, done30 = 0, schedAll = 0, doneAll = 0;
  final weekday = List<int>.filled(7, 0);

  var day = start;
  while (!day.isAfter(end)) {
    final isDone = done.contains(formatDate(day));
    final isSched = scheduled(day);
    if (isDone) {
      run++;
      if (run > best) best = run;
      doneCount++;
      weekday[day.weekday - 1]++;
    } else if (isSched) {
      run = 0;
    }
    if (isSched) {
      schedAll++;
      if (isDone) doneAll++;
      if (!day.isBefore(start30)) {
        sched30++;
        if (isDone) done30++;
      }
    }
    day = DateTime(day.year, day.month, day.day + 1);
  }

  return HabitStats(
    currentStreak: currentStreak(done, end, daysMask: daysMask),
    bestStreak: best,
    doneInWindow: doneCount,
    rate30: sched30 == 0 ? 0 : done30 / sched30,
    rateAll: schedAll == 0 ? 0 : doneAll / schedAll,
    weekdayDone: weekday,
  );
}
