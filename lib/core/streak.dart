import 'format.dart';

/// عدد الأيام المتتالية المنجزة حتى اليوم.
///
/// - إن لم تُنجز العادة اليوم بعد، لا ينقطع التسلسل (يُحسب من الأمس).
/// - الأيام غير المجدولة في [daysMask] تُتجاوز ولا تقطع التسلسل.
/// - [daysMask]: بت لكل يوم، الاثنين = البت 0 ... الأحد = البت 6.
int currentStreak(Set<String> doneDates, DateTime today, {int daysMask = 127}) {
  bool scheduled(DateTime d) => daysMask & (1 << (d.weekday - 1)) != 0;
  DateTime prev(DateTime d) => DateTime(d.year, d.month, d.day - 1);

  var day = DateTime(today.year, today.month, today.day);
  if (!doneDates.contains(formatDate(day))) day = prev(day);

  var streak = 0;
  for (var i = 0; i < 3650; i++) {
    if (doneDates.contains(formatDate(day))) {
      streak++;
    } else if (scheduled(day)) {
      break;
    }
    day = prev(day);
  }
  return streak;
}
