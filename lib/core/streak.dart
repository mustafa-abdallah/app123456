import 'format.dart';

/// عدد الأيام المتتالية المنجزة حتى اليوم.
///
/// - إن لم تُنجز العادة اليوم بعد، لا ينقطع التسلسل (يُحسب من الأمس).
/// - الأيام غير المجدولة تُتجاوز ولا تقطع التسلسل. الجدول إمّا [daysMask] ثابت
///   أو [scheduledOn] (جدول تاريخي يراعي التغييرات والإيقاف المؤقت).
/// - [excused]: أيام إجازة/استثناء، تُتجاوز كذلك.
/// - [daysMask]: بت لكل يوم، الاثنين = البت 0 ... الأحد = البت 6.
int currentStreak(
  Set<String> doneDates,
  DateTime today, {
  int daysMask = 127,
  bool Function(DateTime)? scheduledOn,
  Set<String> excused = const {},
}) {
  bool scheduled(DateTime d) =>
      scheduledOn != null ? scheduledOn(d) : daysMask & (1 << (d.weekday - 1)) != 0;
  DateTime prev(DateTime d) => DateTime(d.year, d.month, d.day - 1);

  var day = DateTime(today.year, today.month, today.day);
  if (!doneDates.contains(formatDate(day))) day = prev(day);

  var streak = 0;
  for (var i = 0; i < 3650; i++) {
    final key = formatDate(day);
    if (doneDates.contains(key)) {
      streak++;
    } else if (scheduled(day) && !excused.contains(key)) {
      break;
    }
    day = prev(day);
  }
  return streak;
}
