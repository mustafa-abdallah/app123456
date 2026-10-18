import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
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
