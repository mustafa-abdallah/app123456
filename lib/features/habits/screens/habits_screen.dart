import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/streak.dart';
import '../../../core/widgets/prompt.dart';
import '../../../database/database.dart';
import '../../../repositories/providers.dart';
import '../providers/habits_providers.dart';
import 'habit_detail_screen.dart';

/// رموز أيام الأسبوع، الفهرس = DateTime.weekday - 1 (الاثنين أولًا).
const _dayLetters = ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'];

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider);
    final logs = ref.watch(habitLogsProvider);
    final masks = ref.watch(habitMasksProvider).valueOrNull ?? const <String, int>{};
    final repo = ref.read(habitsRepositoryProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final name = await promptText(context,
              title: 'عادة جديدة', hint: 'مثال: قراءة ٢٠ دقيقة');
          if (name != null) await repo.create(name);
        },
        child: const Icon(Icons.add),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('العادات',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: habits.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('تعذّر تحميل العادات\n$e')),
            data: (list) {
              if (list.isEmpty) {
                return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.local_fire_department_outlined,
                      size: 56, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 8),
                  const Text('لا توجد عادات بعد'),
                  const Text('اضغط + لبدء عادة جديدة'),
                ]));
              }
              final doneByHabit = <String, Set<String>>{};
              for (final l in logs.valueOrNull ?? const <HabitLog>[]) {
                if (l.status == 'done') {
                  doneByHabit.putIfAbsent(l.habitId, () => {}).add(l.date);
                }
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final h = list[i];
                  final done = doneByHabit[h.id] ?? <String>{};
                  return _HabitCard(
                    habit: h,
                    doneDates: done,
                    daysMask: masks[h.id] ?? 127,
                    onToggle: (date) => repo.toggleDay(h.id, date),
                    onOpen: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => HabitDetailScreen(habitId: h.id))),
                    onRename: () async {
                      final n = await promptText(context,
                          title: 'تعديل الاسم', initial: h.name);
                      if (n != null) await repo.rename(h.id, n);
                    },
                    onDelete: () async {
                      final ok = await confirm(context,
                          title: 'حذف العادة',
                          message: 'سيبقى سجلها محفوظًا. هل تريد حذف «${h.name}»؟',
                          action: 'حذف');
                      if (ok) await repo.softDelete(h.id);
                    },
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _HabitCard extends StatelessWidget {
  const _HabitCard({
    required this.habit,
    required this.doneDates,
    required this.daysMask,
    required this.onToggle,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });
  final Habit habit;
  final Set<String> doneDates;
  final int daysMask;
  final void Function(String date) onToggle;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final streak = currentStreak(doneDates, now, daysMask: daysMask);
    // اليوم أولًا؛ في الواجهة العربية يظهر أقصى اليمين.
    final days = [
      for (var i = 0; i < 7; i++) DateTime(now.year, now.month, now.day - i)
    ];

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(habit.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            if (streak > 0) ...[
              Icon(Icons.local_fire_department, size: 18, color: scheme.primary),
              const SizedBox(width: 2),
              Text('$streak', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)),
            ],
            PopupMenuButton<String>(
              onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('تعديل الاسم')),
                PopupMenuItem(value: 'delete', child: Text('حذف')),
              ],
            ),
          ]),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final d in days)
                  _DayDot(
                    letter: _dayLetters[d.weekday - 1],
                    done: doneDates.contains(formatDate(d)),
                    isToday: d.day == now.day && d.month == now.month,
                    onTap: () => onToggle(formatDate(d)),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot(
      {required this.letter, required this.done, required this.isToday, required this.onTap});
  final String letter;
  final bool done;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(letter, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? scheme.primary : Colors.transparent,
            border: Border.all(
                color: done || isToday ? scheme.primary : scheme.outlineVariant,
                width: isToday ? 2 : 1),
          ),
          child: done ? Icon(Icons.check, size: 18, color: scheme.onPrimary) : null,
        ),
      ]),
    );
  }
}
