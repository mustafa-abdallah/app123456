import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/widgets/prompt.dart';
import '../../../database/database.dart';
import '../../../repositories/providers.dart';
import '../../../repositories/tasks_repository.dart';
import '../providers/tasks_providers.dart';
import 'task_detail_screen.dart';

const _priorityColors = [Color(0xFF9E9E9E), Color(0xFFFFB02E), Color(0xFFEF5350)];

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(taskViewProvider);
    final tasks = ref.watch(tasksProvider);
    final repo = ref.read(tasksRepositoryProvider);
    final projects = ref.watch(projectsProvider).valueOrNull ?? const <Project>[];
    final names = {for (final p in projects) p.id: p.name};

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final d = await _editTask(context, projects: projects);
          if (d != null) {
            await repo.create(d.title,
                priority: d.priority, dueAt: d.dueAt, projectId: d.projectId);
          }
        },
        child: const Icon(Icons.add),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('المهام',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SegmentedButton<TaskView>(
              segments: const [
                ButtonSegment(value: TaskView.active, label: Text('النشطة')),
                ButtonSegment(value: TaskView.overdue, label: Text('المتأخرة')),
                ButtonSegment(value: TaskView.done, label: Text('المنجزة')),
              ],
              selected: {view},
              onSelectionChanged: (s) =>
                  ref.read(taskViewProvider.notifier).state = s.first,
            ),
            const SizedBox(height: 12),
            if (view != TaskView.overdue) const _DayStrip(),
            const SizedBox(height: 8),
            _ProjectChips(projects: projects),
            if (view == TaskView.overdue) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.today),
                label: const Text('نقل كل المتأخرة إلى اليوم'),
                onPressed: () async {
                  final n = await repo.moveOverdueToToday();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(SnackBar(
                        content: Text(n == 0 ? 'لا توجد مهام متأخرة' : 'نُقلت $n مهمة إلى اليوم')));
                },
              ),
            ],
          ]),
        ),
        Expanded(
          child: tasks.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('تعذّر تحميل المهام\n$e')),
            data: (list) {
              if (list.isEmpty) {
                return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.task_alt,
                      size: 56, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 8),
                  Text(switch (view) {
                    TaskView.active => 'لا توجد مهام نشطة',
                    TaskView.overdue => 'لا توجد مهام متأخرة',
                    TaskView.done => 'لم تُنجز أي مهمة بعد',
                  }),
                  if (view == TaskView.active) const Text('اضغط + لإضافة مهمة'),
                ]));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final t = list[i];
                  return Dismissible(
                    key: ValueKey(t.id),
                    background: Container(
                      decoration: BoxDecoration(
                          color: Colors.red.withAlpha(60),
                          borderRadius: BorderRadius.circular(20)),
                      alignment: Alignment.center,
                      child: const Icon(Icons.delete_outline),
                    ),
                    onDismissed: (_) {
                      repo.softDelete(t.id);
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(SnackBar(
                          content: const Text('حُذفت المهمة'),
                          action: SnackBarAction(
                              label: 'تراجع', onPressed: () => repo.restore(t.id)),
                        ));
                    },
                    child: _TaskTile(
                      task: t,
                      projectName: names[t.projectId],
                      onToggle: () => _toggleTask(context, repo, t),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TaskDetailScreen(taskId: t.id))),
                    ),
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

class _TaskTile extends ConsumerWidget {
  const _TaskTile(
      {required this.task,
      required this.onToggle,
      required this.onTap,
      this.projectName});
  final Task task;
  final String? projectName;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final done = task.status == 'done';
    final due = task.dueAt;
    final subs = ref.watch(subtasksProvider(task.id)).valueOrNull ?? const <Task>[];
    final subsDone = subs.where((x) => x.status == 'done').length;
    final deps = ref.watch(taskDepsProvider(task.id)).valueOrNull ?? const <Task>[];
    final blocked = !done && deps.any((x) => x.status != 'done');
    final repeats = (task.recurrenceRule ?? '').isNotEmpty;
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final overdue = !done && due != null && due.isBefore(startOfToday);
    final pri = task.priority.clamp(0, 2);

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(children: [
            Checkbox(value: done, onChanged: (_) => onToggle()),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: done ? TextDecoration.lineThrough : null,
                          color: done ? scheme.onSurface.withAlpha(120) : null,
                        )),
                if (due != null || projectName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 12, children: [
                      if (due != null)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.event,
                              size: 14, color: overdue ? Colors.red : scheme.primary),
                          const SizedBox(width: 4),
                          Text(formatDate(due),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: overdue ? Colors.red : scheme.primary)),
                        ]),
                      if (projectName != null)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.label_outline, size: 14, color: scheme.secondary),
                          const SizedBox(width: 4),
                          Text(projectName!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.secondary)),
                        ]),
                    ]),
                  ),
                if (subs.isNotEmpty || repeats || blocked)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 12, children: [
                      if (subs.isNotEmpty)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.checklist,
                              size: 14, color: scheme.onSurface.withAlpha(150)),
                          const SizedBox(width: 4),
                          Text('$subsDone/${subs.length}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ]),
                      if (repeats)
                        Icon(Icons.repeat, size: 14, color: scheme.onSurface.withAlpha(150)),
                      if (blocked)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.lock_outline, size: 14, color: Colors.orange),
                          const SizedBox(width: 4),
                          Text('بانتظار مهمة أخرى',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.orange)),
                        ]),
                    ]),
                  ),
              ]),
            ),
            if (!done && pri > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.flag, color: _priorityColors[pri]),
              ),
          ]),
        ),
      ),
    );
  }
}

class _TaskDraft {
  const _TaskDraft(this.title, this.priority, this.dueAt, this.projectId)
      : remove = false;
  const _TaskDraft.remove()
      : title = '',
        priority = 0,
        dueAt = null,
        projectId = null,
        remove = true;
  final bool remove;
  final String title;
  final int priority;
  final DateTime? dueAt;
  final String? projectId;
}

Future<_TaskDraft?> _editTask(BuildContext context,
        {Task? existing, required List<Project> projects}) =>
    showModalBottomSheet<_TaskDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TaskSheet(existing: existing, projects: projects),
    );

class _TaskSheet extends StatefulWidget {
  const _TaskSheet({this.existing, required this.projects});
  final Task? existing;
  final List<Project> projects;

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late int _priority = (widget.existing?.priority ?? 0).clamp(0, 2);
  late DateTime? _due = widget.existing?.dueAt;
  late String? _projectId = widget.existing?.projectId;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _due = d);
  }

  void _save() {
    final t = _title.text.trim();
    if (t.isEmpty) return;
    Navigator.pop(context, _TaskDraft(t, _priority, _due, _projectId));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.existing == null ? 'مهمة جديدة' : 'تعديل المهمة',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'ما الذي تريد إنجازه؟'),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 16),
        SegmentedButton<int>(
          segments: [
            for (var i = 0; i < 3; i++)
              ButtonSegment(value: i, label: Text(TasksRepository.priorityLabels[i])),
          ],
          selected: {_priority},
          onSelectionChanged: (s) => setState(() => _priority = s.first),
        ),
        const SizedBox(height: 12),
        Row(children: [
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event),
            label: Text(_due == null ? 'تاريخ الاستحقاق' : formatDate(_due!)),
          ),
          if (_due != null)
            IconButton(
                tooltip: 'إزالة التاريخ',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _due = null)),
        ]),
        if (widget.projects.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            ChoiceChip(
              label: const Text('بدون تصنيف'),
              selected: _projectId == null,
              onSelected: (_) => setState(() => _projectId = null),
            ),
            for (final p in widget.projects)
              ChoiceChip(
                label: Text(p.name),
                selected: _projectId == p.id,
                onSelected: (_) => setState(() => _projectId = p.id),
              ),
          ]),
        ],
        const SizedBox(height: 16),
        SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _save, child: const Text('حفظ'))),
        if (widget.existing != null)
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              icon: const Icon(Icons.delete_outline),
              label: const Text('حذف المهمة'),
              onPressed: () => Navigator.pop(context, const _TaskDraft.remove()),
            ),
          ),
      ]),
    );
  }
}


const _dayLetters = ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'];

/// شريط أيام أفقي: «الكل» ثم اليوم و13 يومًا قادمة.
class _DayStrip extends ConsumerWidget {
  const _DayStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(taskDayFilterProvider);
    final now = DateTime.now();
    final days = [
      for (var i = 0; i < 14; i++) DateTime(now.year, now.month, now.day + i)
    ];
    final scheme = Theme.of(context).colorScheme;

    Widget item(
        {required String top, required String bottom, required bool on, required VoidCallback onTap}) {
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Material(
          color: on ? scheme.primary : scheme.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: SizedBox(
              width: 52,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(top,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: on ? scheme.onPrimary : null)),
                const SizedBox(height: 4),
                Text(bottom,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: on ? scheme.onPrimary : null)),
              ]),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 64,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        item(
            top: 'كل',
            bottom: '∞',
            on: selected == null,
            onTap: () => ref.read(taskDayFilterProvider.notifier).state = null),
        for (final d in days)
          item(
            top: _dayLetters[d.weekday - 1],
            bottom: '${d.day}',
            on: selected == d,
            onTap: () => ref.read(taskDayFilterProvider.notifier).state = d,
          ),
      ]),
    );
  }
}

/// تصنيفات المهام: اختيار تصنيف، إضافة بالزر، وحذف بالضغط المطوّل.
class _ProjectChips extends ConsumerWidget {
  const _ProjectChips({required this.projects});
  final List<Project> projects;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(taskProjectFilterProvider);
    final repo = ref.read(projectsRepositoryProvider);

    return SizedBox(
      height: 44,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: ChoiceChip(
            label: const Text('كل التصنيفات'),
            selected: selected == null,
            onSelected: (_) =>
                ref.read(taskProjectFilterProvider.notifier).state = null,
          ),
        ),
        for (final p in projects)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: GestureDetector(
              onLongPress: () async {
                final ok = await confirm(context,
                    title: 'حذف التصنيف',
                    message: 'ستبقى مهام «${p.name}» دون تصنيف. هل تريد الحذف؟',
                    action: 'حذف');
                if (!ok) return;
                if (selected == p.id) {
                  ref.read(taskProjectFilterProvider.notifier).state = null;
                }
                await repo.delete(p.id);
              },
              child: ChoiceChip(
                label: Text(p.name),
                selected: selected == p.id,
                onSelected: (_) =>
                    ref.read(taskProjectFilterProvider.notifier).state = p.id,
              ),
            ),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 16),
          label: const Text('تصنيف'),
          onPressed: () async {
            final name = await promptText(context,
                title: 'تصنيف جديد', hint: 'مثال: دراسة، عمل، بيت');
            if (name != null) await repo.create(name);
          },
        ),
      ]),
    );
  }
}


/// يبدّل حالة المهمة، ويُنبّه إن كانت تنتظر مهمة أخرى.
Future<void> _toggleTask(BuildContext context, TasksRepository repo, Task t) async {
  final r = await repo.toggle(t);
  if (!r.ok && context.mounted) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
          content: Text('أنجز أولًا: ${r.blockers.map((b) => b.title).join('، ')}')));
  }
}
