import 'format.dart';

/// فترة من جدول العادة: من [from] إلى [to] (شاملة؛ null = مفتوحة) بأيام [mask].
/// [mask]: بت لكل يوم، الاثنين = البت 0 ... الأحد = البت 6.
class ScheduleSpan {
  const ScheduleSpan(this.from, this.to, this.mask);
  final String from; // yyyy-MM-dd
  final String? to; // yyyy-MM-dd
  final int mask;
}

/// هل كان [d] يومًا مستهدفًا حسب الجدول الساري في ذلك اليوم؟
///
/// - تغيير أيام العادة لا يمسّ الماضي: كل يوم يُحكم عليه بالجدول الذي كان ساريًا وقتها.
/// - أيام الإيقاف المؤقت وما قبل إنشاء العادة غير مستهدفة.
/// - بلا أي جدول (بيانات قديمة): كل الأيام مستهدفة.
bool scheduledOnDate(List<ScheduleSpan> spans, DateTime d) {
  if (spans.isEmpty) return true;
  final key = formatDate(d);
  ScheduleSpan? best;
  for (final s in spans) {
    final started = s.from.compareTo(key) <= 0;
    final notEnded = s.to == null || key.compareTo(s.to!) <= 0;
    if (started && notEnded && (best == null || s.from.compareTo(best.from) >= 0)) {
      best = s;
    }
  }
  if (best == null) return false;
  return best.mask & (1 << (d.weekday - 1)) != 0;
}

/// الأيام المضبوطة حاليًا: الفترة المفتوحة، وإن كانت العادة متوقفة فآخر فترة، وإلا كل الأيام.
int currentMaskOf(List<ScheduleSpan> spans) {
  if (spans.isEmpty) return 127;
  for (final s in spans) {
    if (s.to == null) return s.mask;
  }
  var last = spans.first;
  for (final s in spans) {
    if (s.from.compareTo(last.from) >= 0) last = s;
  }
  return last.mask;
}
