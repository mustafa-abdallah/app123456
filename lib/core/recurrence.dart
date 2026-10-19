/// قواعد تكرار المهام: '' (لا تتكرر) | daily | weekly | monthly
const recurrenceLabels = {
  '': 'لا تتكرر',
  'daily': 'يوميًا',
  'weekly': 'أسبوعيًا',
  'monthly': 'شهريًا',
};

int _daysInMonth(int y, int m) => DateTime(y, m + 1, 0).day;

/// الموعد التالي بعد [d] حسب [rule] مع الحفاظ على الوقت.
/// الشهري: إن لم يوجد اليوم في الشهر التالي (مثل 31) يُستخدم آخر يوم فيه.
DateTime nextOccurrence(DateTime d, String rule) {
  switch (rule) {
    case 'daily':
      return DateTime(d.year, d.month, d.day + 1, d.hour, d.minute);
    case 'weekly':
      return DateTime(d.year, d.month, d.day + 7, d.hour, d.minute);
    case 'monthly':
      final y = d.month == 12 ? d.year + 1 : d.year;
      final m = d.month == 12 ? 1 : d.month + 1;
      final last = _daysInMonth(y, m);
      return DateTime(y, m, d.day > last ? last : d.day, d.hour, d.minute);
    default:
      return d;
  }
}

/// أول موعد تالٍ لا يقع قبل [today]. فمهمة يومية متأخرة أسبوعًا
/// تُنجَز اليوم فتظهر نسختها التالية اليوم/غدًا لا قبل أسبوع.
DateTime nextDueAfter(DateTime base, String rule, DateTime today) {
  var next = nextOccurrence(base, rule);
  var guard = 0;
  while (next.isBefore(today) && guard++ < 2000) {
    final n = nextOccurrence(next, rule);
    if (n == next) break; // قاعدة غير معروفة
    next = n;
  }
  return next;
}
