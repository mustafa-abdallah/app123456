import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/habit_schedule.dart';
import '../../../database/database.dart';
import '../../../repositories/providers.dart';

/// نافذة السجل المعروضة: نحمّل سنة كاملة لحساب التسلسل بدقة.
const habitLogWindowDays = 365;

final habitsProvider = StreamProvider.autoDispose<List<Habit>>(
    (ref) => ref.watch(habitsRepositoryProvider).watchActive());

final habitLogsProvider = StreamProvider.autoDispose<List<HabitLog>>((ref) {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day - habitLogWindowDays);
  return ref.watch(habitsRepositoryProvider).watchLogsSince(formatDate(from));
});

final habitMasksProvider = FutureProvider.autoDispose<Map<String, int>>((ref) {
  // يُعاد الحساب عند تغيّر قائمة العادات.
  ref.watch(habitsProvider);
  return ref.watch(habitsRepositoryProvider).masks();
});

/// كل فترات الجداول مجمّعة بحسب العادة (تتحدث فور أي تغيير في الأيام أو الإيقاف).
final habitSchedulesProvider =
    StreamProvider.autoDispose<Map<String, List<HabitSchedule>>>((ref) {
  return ref.watch(habitsRepositoryProvider).watchSchedules().map((rows) {
    final m = <String, List<HabitSchedule>>{};
    for (final s in rows) {
      (m[s.habitId] ??= []).add(s);
    }
    return m;
  });
});

List<ScheduleSpan> spansOf(Iterable<HabitSchedule>? list) => [
      for (final s in list ?? const <HabitSchedule>[])
        ScheduleSpan(s.validFrom, s.validTo, s.daysMask),
    ];

/// سجل عادة واحدة مفهرسًا بالتاريخ (yyyy-MM-dd) لاستخدامه في الإحصاءات والعرض.
class HabitDays {
  const HabitDays(this.done, this.excused, this.partial, this.values);

  /// أيام بلغ فيها الهدف.
  final Set<String> done;

  /// أيام إجازة.
  final Set<String> excused;

  /// أيام جزئية: التاريخ -> نسبة الإنجاز (0..1).
  final Map<String, double> partial;

  /// الكمية المسجّلة لكل يوم.
  final Map<String, double> values;
}

HabitDays habitDaysFor(Iterable<HabitLog> logs, double target) {
  final t = target <= 0 ? 1.0 : target;
  final done = <String>{}, excused = <String>{};
  final partial = <String, double>{}, values = <String, double>{};
  for (final l in logs) {
    switch (l.status) {
      case 'done':
        done.add(l.date);
        values[l.date] = l.value;
      case 'partial':
        partial[l.date] = (l.value / t).clamp(0.0, 1.0).toDouble();
        values[l.date] = l.value;
      case 'excused':
        excused.add(l.date);
    }
  }
  return HabitDays(done, excused, partial, values);
}
