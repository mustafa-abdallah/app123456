import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../database/database.dart';
import '../../../repositories/notes_repository.dart';
import '../../../repositories/providers.dart';
import '../../habits/providers/habits_providers.dart';
import '../../settings/providers/settings_providers.dart';
import '../../settings/screens/settings_screen.dart';
import '../../tasks/providers/tasks_providers.dart';

final _recentNotesProvider = StreamProvider.autoDispose<List<Note>>(
    (ref) => ref.watch(notesRepositoryProvider).watch(const NotesFilter()));

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final greeting = now.hour < 12 ? 'صباح الخير' : 'مساء الخير';
    final todayKey = formatDate(now);
    final endOfToday = DateTime(now.year, now.month, now.day + 1);

    final tasks = ref.watch(activeTasksProvider).valueOrNull ?? const <Task>[];
    final dueNow = tasks
        .where((t) => t.dueAt != null && t.dueAt!.isBefore(endOfToday))
        .length;

    final habits = ref.watch(habitsProvider).valueOrNull ?? const <Habit>[];
    final logs = ref.watch(habitLogsProvider).valueOrNull ?? const <HabitLog>[];
    final doneToday = logs
        .where((l) => l.date == todayKey && l.status == 'done')
        .map((l) => l.habitId)
        .toSet()
        .intersection(habits.map((h) => h.id).toSet())
        .length;

    final notes = ref.watch(_recentNotesProvider).valueOrNull ?? const <Note>[];

    final backup = ref.watch(lastBackupProvider);
    final showBackupHint = backup.hasValue &&
        (backup.value == null || now.difference(backup.value!).inDays >= 7);

    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(greeting, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text('لوحة التحكم',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ]),
        ),
        IconButton(
          tooltip: 'الإعدادات',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
      ]),
      const SizedBox(height: 16),
      if (showBackupHint) ...[
        _BackupHint(last: backup.value),
        const SizedBox(height: 12),
      ],
      Row(children: [
        Expanded(
          child: _StatCard(
              icon: Icons.check_circle_outline,
              color: const Color(0xFF42A5F5),
              value: '$dueNow',
              label: 'مهام اليوم والمتأخرة',
              sub: 'من ${tasks.length} نشطة'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
              icon: Icons.local_fire_department_outlined,
              color: const Color(0xFFFFB02E),
              value: '$doneToday/${habits.length}',
              label: 'عادات اليوم',
              sub: habits.isEmpty ? 'أضف عادة' : 'منجزة'),
        ),
      ]),
      const SizedBox(height: 20),
      Text('آخر الملاحظات', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (notes.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('لا توجد ملاحظات بعد'))
      else
        for (final n in notes.take(3))
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surface,
            child: ListTile(
              title: Text(n.title.isEmpty ? 'بدون عنوان' : n.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(formatDateTime(n.updatedAt)),
            ),
          ),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.icon,
      required this.color,
      required this.value,
      required this.label,
      required this.sub});
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(dark ? 45 : 80),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Text(sub, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

/// تنبيه لطيف عند عدم وجود نسخة احتياطية حديثة (أسبوع فأكثر).
class _BackupHint extends StatelessWidget {
  const _BackupHint({required this.last});
  final DateTime? last;

  @override
  Widget build(BuildContext context) {
    final days = last == null ? null : DateTime.now().difference(last!).inDays;
    const red = Color(0xFFEF5350);
    return Material(
      color: red.withAlpha(40),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.shield_outlined, color: red),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    days == null
                        ? 'لم تأخذ نسخة احتياطية بعد'
                        : 'آخر نسخة احتياطية قبل $days يومًا',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Text('بياناتك على هذا الجهاز فقط — احفظ نسخة في مكان آمن'),
              ]),
            ),
            const Icon(Icons.chevron_left),
          ]),
        ),
      ),
    );
  }
}
