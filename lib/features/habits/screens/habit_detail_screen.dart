import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/habit_stats.dart';
import '../../../database/database.dart';
import '../providers/habits_providers.dart';

const _dayNames = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
const _dayLetters = ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'];

/// إحصاءات عادة واحدة: التسلسل، نسبة الالتزام، أفضل الأيام، وخريطة السنة.
class HabitDetailScreen extends ConsumerWidget {
  const HabitDetailScreen({super.key, required this.habitId});
  final String habitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider).valueOrNull ?? const <Habit>[];
    final logs = ref.watch(habitLogsProvider).valueOrNull ?? const <HabitLog>[];
    final masks = ref.watch(habitMasksProvider).valueOrNull ?? const <String, int>{};

    Habit? habit;
    for (final h in habits) {
      if (h.id == habitId) habit = h;
    }
    if (habit == null) {
      return Scaffold(
          appBar: AppBar(), body: const Center(child: Text('العادة غير موجودة')));
    }

    final done = {
      for (final l in logs)
        if (l.habitId == habitId && l.status == 'done') l.date
    };
    final now = DateTime.now();
    final stats = computeHabitStats(done, now,
        daysMask: masks[habitId] ?? 127,
        since: habit.createdAt,
        windowDays: habitLogWindowDays);

    return Scaffold(
      appBar: AppBar(title: Text(habit.name)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Row(children: [
          Expanded(child: _Stat('${stats.currentStreak}', 'التسلسل الحالي', Icons.local_fire_department)),
          const SizedBox(width: 10),
          Expanded(child: _Stat('${stats.bestStreak}', 'أفضل تسلسل', Icons.emoji_events_outlined)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _Stat(_pct(stats.rate30), 'آخر 30 يومًا', Icons.calendar_month_outlined)),
          const SizedBox(width: 10),
          Expanded(child: _Stat(_pct(stats.rateAll), 'منذ البداية', Icons.insights_outlined)),
        ]),
        const SizedBox(height: 20),
        Text('أفضل الأيام', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _WeekdayBars(counts: stats.weekdayDone),
        const SizedBox(height: 20),
        Text('آخر سنة', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _YearHeatmap(done: done, today: now),
        const SizedBox(height: 8),
        Text('${stats.doneInWindow} يوم إنجاز في آخر سنة',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  static String _pct(double r) => '${(r * 100).round()}%';
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: scheme.surface, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Icon(icon, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

class _WeekdayBars extends StatelessWidget {
  const _WeekdayBars({required this.counts});
  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final max = counts.fold<int>(0, (a, b) => b > a ? b : a);
    final bestIdx = max == 0 ? -1 : counts.indexOf(max);
    const maxH = 90.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
      decoration: BoxDecoration(
          color: scheme.surface, borderRadius: BorderRadius.circular(20)),
      child: Column(children: [
        SizedBox(
          height: maxH + 20,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('${counts[i]}', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 2),
                  Container(
                    width: 24,
                    height: max == 0 ? 4 : 4 + (maxH - 4) * counts[i] / max,
                    decoration: BoxDecoration(
                      color: i == bestIdx ? scheme.primary : scheme.primary.withAlpha(90),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ]),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final l in _dayLetters)
            SizedBox(
                width: 24,
                child: Text(l,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall)),
        ]),
        if (bestIdx >= 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('أكثر يوم تلتزم فيه: ${_dayNames[bestIdx]}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ]),
    );
  }
}

/// خريطة حرارية: عمود لكل أسبوع (الأحدث عند الحافة الأولى)، وصف لكل يوم.
class _YearHeatmap extends StatelessWidget {
  const _YearHeatmap({required this.done, required this.today});
  final Set<String> done;
  final DateTime today;

  static const _weeks = 53;
  static const _cell = 14.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = DateTime(today.year, today.month, today.day);
    final thisWeekStart = DateTime(t.year, t.month, t.day - (t.weekday - 1));

    Widget cell(DateTime d) {
      final future = d.isAfter(t);
      final isDone = done.contains(formatDate(d));
      return Container(
        width: _cell,
        height: _cell,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          color: future
              ? Colors.transparent
              : isDone
                  ? scheme.primary
                  : scheme.onSurface.withAlpha(25),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: scheme.surface, borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var w = 0; w < _weeks; w++)
            Column(children: [
              for (var d = 0; d < 7; d++)
                cell(DateTime(thisWeekStart.year, thisWeekStart.month,
                    thisWeekStart.day - 7 * w + d)),
            ]),
        ]),
      ),
    );
  }
}
