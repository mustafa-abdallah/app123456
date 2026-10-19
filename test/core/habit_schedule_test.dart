import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/core/habit_schedule.dart';

void main() {
  // الاثنين=بت0، الأربعاء=بت2، الجمعة=بت4  => 1+4+16 = 21
  const monWedFri = 21;

  test('تغيير الأيام لا يمسّ الماضي: كل يوم يُحكم عليه بجدوله وقتها', () {
    const spans = [
      ScheduleSpan('2026-01-01', '2026-10-10', monWedFri),
      ScheduleSpan('2026-10-11', null, 127),
    ];
    expect(scheduledOnDate(spans, DateTime(2026, 10, 5)), isTrue); // الاثنين
    expect(scheduledOnDate(spans, DateTime(2026, 10, 6)), isFalse); // الثلاثاء (جدول قديم)
    expect(scheduledOnDate(spans, DateTime(2026, 10, 13)), isTrue); // الثلاثاء (جدول جديد)
  });

  test('ما قبل إنشاء العادة وفترات الإيقاف المؤقت غير مستهدفة', () {
    const spans = [
      ScheduleSpan('2026-01-01', '2026-10-10', 127),
      ScheduleSpan('2026-10-20', null, 127),
    ];
    expect(scheduledOnDate(spans, DateTime(2025, 12, 31)), isFalse);
    expect(scheduledOnDate(spans, DateTime(2026, 10, 15)), isFalse); // أثناء الإيقاف
    expect(scheduledOnDate(spans, DateTime(2026, 10, 25)), isTrue);
  });

  test('بلا جدول (بيانات قديمة) كل الأيام مستهدفة', () {
    expect(scheduledOnDate(const [], DateTime(2026, 10, 6)), isTrue);
  });

  test('الأيام الحالية: المفتوحة، ثم آخر فترة عند الإيقاف، ثم الافتراضي', () {
    expect(currentMaskOf(const []), 127);
    expect(
        currentMaskOf(const [
          ScheduleSpan('2026-01-01', '2026-05-01', 127),
          ScheduleSpan('2026-05-02', null, monWedFri),
        ]),
        monWedFri);
    expect(
        currentMaskOf(const [
          ScheduleSpan('2026-01-01', '2026-05-01', 127),
          ScheduleSpan('2026-05-02', '2026-06-01', monWedFri),
        ]),
        monWedFri); // متوقفة: آخر فترة
  });
}
