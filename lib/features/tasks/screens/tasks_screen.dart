import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../database/database.dart';
import '../../../repositories/providers.dart';
import '../../../repositories/tasks_repository.dart';
import '../providers/tasks_providers.dart';

const _priorityColors = [Color(0xFF9E9E9E), Color(0xFFFFB02E), Color(0xFFEF5350)];

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(taskViewProvider);
    final tasks = ref.watch(tasksProvider);
    final repo = ref.read(tasksRepositoryProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final d = await _editTask(context);
          if (d != null) {
            await repo.create(d.title, priority: d.priority, dueAt: d.dueAt);
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
                ButtonSegment(value: TaskView.done, label: Text('المنجزة')),
              ],
              selected: {view},
              onSelectionChanged: (s) =>
                  ref.read(taskViewProvider.notifier).state = s.first,
            ),
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
                  Text(view == TaskView.active
                      ? 'لا توجد مهام نشطة'
                      : 'لم تُنجز أي مهمة بعد'),
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
                      onToggle: () => repo.toggle(t),
                      onTap: () async {
                        final d = await _editTask(context, existing: t);
                        if (d != null) {
                          await repo.update(t.id,
                              title: d.title, priority: d.priority, dueAt: d.dueAt);
                        }
                      },
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

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.onToggle, required this.onTap});
  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = task.status == 'done';
    final due = task.dueAt;
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
                if (due != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      Icon(Icons.event,
                          size: 14, color: overdue ? Colors.red : scheme.primary),
                      const SizedBox(width: 4),
                      Text(formatDate(due),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: overdue ? Colors.red : scheme.primary)),
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
  const _TaskDraft(this.title, this.priority, this.dueAt);
  final String title;
  final int priority;
  final DateTime? dueAt;
}

Future<_TaskDraft?> _editTask(BuildContext context, {Task? existing}) =>
    showModalBottomSheet<_TaskDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TaskSheet(existing: existing),
    );

class _TaskSheet extends StatefulWidget {
  const _TaskSheet({this.existing});
  final Task? existing;

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late int _priority = (widget.existing?.priority ?? 0).clamp(0, 2);
  late DateTime? _due = widget.existing?.dueAt;

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
    Navigator.pop(context, _TaskDraft(t, _priority, _due));
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
        const SizedBox(height: 16),
        SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _save, child: const Text('حفظ'))),
      ]),
    );
  }
}
