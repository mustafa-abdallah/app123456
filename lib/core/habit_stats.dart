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
///
/// - [scheduledOn]: جدول تاريخي (يُفضَّل على [daysMask] الثابت).
/// - [excused]: أيام إجازة، محايدة (لا تُحسب في النسبة ولا تقطع التسلسل).
/// - [partial]: تاريخ -> نسبة الإنجاز الجزئي (0..1)، تُحسب جزئيًا في النسب فقط؛
///   التسلسل يتطلب إنجازًا كاملًا.
HabitStats computeHabitStats(
  Set<String> done,
  DateTime today, {
  int daysMask = 127,
  DateTime? since,
  int windowDays = 365,
  bool Function(DateTime)? scheduledOn,
  Set<String> excused = const {},
  Map<String, double> partial = const {},
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
  bool scheduled(DateTime d) =>
      scheduledOn != null ? scheduledOn(d) : daysMask & (1 << (d.weekday - 1)) != 0;

  var best = 0, run = 0, doneCount = 0;
  var sched30 = 0, schedAll = 0;
  var credit30 = 0.0, creditAll = 0.0;
  final weekday = List<int>.filled(7, 0);

  var day = start;
  while (!day.isAfter(end)) {
    final key = formatDate(day);
    final isDone = done.contains(key);
    final isExcused = !isDone && excused.contains(key);
    final isSched = scheduled(day) && !isExcused;
    if (isDone) {
      run++;
      if (run > best) best = run;
      doneCount++;
      weekday[day.weekday - 1]++;
    } else if (isSched) {
      run = 0;
    }
    if (isSched) {
      final credit = isDone ? 1.0 : (partial[key] ?? 0.0);
      schedAll++;
      creditAll += credit;
      if (!day.isBefore(start30)) {
        sched30++;
        credit30 += credit;
      }
    }
    day = DateTime(day.year, day.month, day.day + 1);
  }

  return HabitStats(
    currentStreak: currentStreak(done, end,
        daysMask: daysMask, scheduledOn: scheduledOn, excused: excused),
    bestStreak: best,
    doneInWindow: doneCount,
    rate30: sched30 == 0 ? 0 : credit30 / sched30,
    rateAll: schedAll == 0 ? 0 : creditAll / schedAll,
    weekdayDone: weekday,
  );
}
