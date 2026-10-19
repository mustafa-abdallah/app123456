import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/recurrence.dart';
import '../../../core/widgets/prompt.dart';
import '../../../database/database.dart';
import '../../../repositories/notes_repository.dart';
import '../../../repositories/providers.dart';
import '../../../repositories/tasks_repository.dart';
import '../../notes/screens/note_editor_screen.dart';
import '../providers/tasks_providers.dart';

/// تفاصيل المهمة: العنوان والوصف والأولوية والموعد والتكرار والتصنيف،
/// والمهام الفرعية والاعتماديات والملاحظات المرتبطة. التغييرات تُحفظ فورًا.
class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final String taskId;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  late final TasksRepository _repo;
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _sub = TextEditingController();
  Timer? _debounce;
  bool _ready = false;
  String _lastTitle = '';
  String _lastDesc = '';

  @override
  void initState() {
    super.initState();
    _repo = ref.read(tasksRepositoryProvider);
    _init();
  }

  Future<void> _init() async {
    final t = await _repo.getById(widget.taskId);
    if (!mounted) return;
    if (t == null) {
      Navigator.pop(context);
      return;
    }
    _title.text = t.title;
    _desc.text = t.description;
    _lastTitle = t.title;
    _lastDesc = t.description;
    _title.addListener(_changed);
    _desc.addListener(_changed);
    setState(() => _ready = true);
  }

  void _changed() {
    if (!_ready) return;
    if (_title.text.trim() == _lastTitle && _desc.text == _lastDesc) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _saveText);
  }

  Future<void> _saveText() async {
    final t = _title.text.trim();
    if (t.isEmpty) return; // العنوان مطلوب
    final d = _desc.text;
    await _repo.updateFields(
        widget.taskId, TasksCompanion(title: Value(t), description: Value(d)));
    _lastTitle = t;
    _lastDesc = d;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_ready) {
      final t = _title.text.trim(), d = _desc.text;
      if (t.isNotEmpty && (t != _lastTitle || d != _lastDesc)) {
        unawaited(_repo.updateFields(
            widget.taskId, TasksCompanion(title: Value(t), description: Value(d))));
      }
    }
    _title.dispose();
    _desc.dispose();
    _sub.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _toggle(Task t) async {
    final r = await _repo.toggle(t);
    if (!r.ok && mounted) {
      _snack('أنجز أولًا: ${r.blockers.map((b) => b.title).join('، ')}');
    }
  }

  Future<void> _pickDue(Task t) async {
    final d = await showDatePicker(
      context: context,
      initialDate: t.dueAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    await _repo.updateFields(
        widget.taskId, TasksCompanion(dueAt: Value(DateTime(d.year, d.month, d.day))));
  }

  Future<void> _setDue(DateTime? d) => _repo.updateFields(
      widget.taskId, TasksCompanion(dueAt: Value<DateTime?>(d)));

  Future<void> _addDependency() async {
    final all = await _repo.openTasks(excludeId: widget.taskId);
    final already = (ref.read(taskDepsProvider(widget.taskId)).valueOrNull ?? const <Task>[])
        .map((t) => t.id)
        .toSet();
    final options = all.where((t) => !already.contains(t.id)).toList();
    if (!mounted) return;
    if (options.isEmpty) {
      _snack('لا توجد مهام أخرى لتعتمد عليها');
      return;
    }
    final picked = await showDialog<Task>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('تعتمد هذه المهمة على…'),
        children: [
          for (final t in options)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, t), child: Text(t.title)),
        ],
      ),
    );
    if (picked == null) return;
    final ok = await _repo.addDependency(widget.taskId, picked.id);
    if (!ok && mounted) _snack('لا يمكن: ينتج عنه اعتماد دائري');
  }

  Future<void> _linkNote() async {
    final all = await ref.read(notesRepositoryProvider).watch(const NotesFilter()).first;
    final linked = (ref.read(taskNotesProvider(widget.taskId)).valueOrNull ?? const <Note>[])
        .map((n) => n.id)
        .toSet();
    final options = all.where((n) => !linked.contains(n.id)).take(100).toList();
    if (!mounted) return;
    if (options.isEmpty) {
      _snack('لا توجد ملاحظات لربطها');
      return;
    }
    final picked = await showDialog<Note>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('ربط بملاحظة'),
        children: [
          for (final n in options)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, n),
                child: Text(n.title.isEmpty ? 'بدون عنوان' : n.title)),
        ],
      ),
    );
    if (picked != null) await _repo.linkNote(widget.taskId, picked.id);
  }

  Future<void> _addSubtask(String v) async {
    final t = v.trim();
    if (t.isEmpty) return;
    await _repo.create(t, parentTaskId: widget.taskId);
    _sub.clear();
  }

  Future<void> _delete() async {
    final ok = await confirm(context,
        title: 'حذف المهمة؟',
        message: 'ستُحذف معها مهامها الفرعية من القوائم. يمكنك التراجع بعد الحذف مباشرة.',
        action: 'حذف');
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await _repo.softDelete(widget.taskId);
    if (!mounted) return;
    Navigator.pop(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: const Text('حُذفت المهمة'),
        action: SnackBarAction(
            label: 'تراجع', onPressed: () => _repo.restore(widget.taskId)),
      ));
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(t, style: Theme.of(context).textTheme.titleSmall),
      );

  @override
  Widget build(BuildContext context) {
    final task = ref.watch(taskProvider(widget.taskId)).valueOrNull;
    if (!_ready || task == null) {
      return Scaffold(
          appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final subs = ref.watch(subtasksProvider(widget.taskId)).valueOrNull ?? const <Task>[];
    final deps = ref.watch(taskDepsProvider(widget.taskId)).valueOrNull ?? const <Task>[];
    final notes = ref.watch(taskNotesProvider(widget.taskId)).valueOrNull ?? const <Note>[];
    final projects = ref.watch(projectsProvider).valueOrNull ?? const <Project>[];
    final done = task.status == 'done';
    final rule = task.recurrenceRule ?? '';
    final today = startOfDay(DateTime.now());
    final subsDone = subs.where((s) => s.status == 'done').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل المهمة'),
        actions: [
          IconButton(
              tooltip: 'حذف',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
            decoration:
                const InputDecoration(hintText: 'عنوان المهمة', border: InputBorder.none),
          ),
        ),
        CheckboxListTile(
          value: done,
          onChanged: (_) => _toggle(task),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(done ? 'منجزة' : 'غير منجزة'),
        ),

        _section('الأولوية'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<int>(
            segments: [
              for (var i = 0; i < 3; i++)
                ButtonSegment(value: i, label: Text(TasksRepository.priorityLabels[i])),
            ],
            selected: {task.priority.clamp(0, 2)},
            onSelectionChanged: (s) => _repo.updateFields(
                widget.taskId, TasksCompanion(priority: Value(s.first))),
          ),
        ),

        _section('الموعد'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(task.dueAt == null ? 'تحديد تاريخ' : formatDate(task.dueAt!)),
              onPressed: () => _pickDue(task),
            ),
            ActionChip(label: const Text('اليوم'), onPressed: () => _setDue(today)),
            ActionChip(
                label: const Text('غدًا'),
                onPressed: () => _setDue(DateTime(today.year, today.month, today.day + 1))),
            if (task.dueAt != null)
              ActionChip(
                  avatar: const Icon(Icons.close, size: 16),
                  label: const Text('إزالة'),
                  onPressed: () => _setDue(null)),
          ]),
        ),

        _section('التكرار'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, children: [
            for (final e in recurrenceLabels.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: rule == e.key,
                onSelected: (_) => _repo.updateFields(widget.taskId,
                    TasksCompanion(recurrenceRule: Value<String?>(e.key.isEmpty ? null : e.key))),
              ),
          ]),
        ),
        if (rule.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text('عند إنجاز المهمة تُنشأ نسختها التالية تلقائيًا.'),
          ),

        if (projects.isNotEmpty) ...[
          _section('التصنيف'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, children: [
              ChoiceChip(
                label: const Text('بدون تصنيف'),
                selected: task.projectId == null,
                onSelected: (_) => _repo.updateFields(
                    widget.taskId, const TasksCompanion(projectId: Value<String?>(null))),
              ),
              for (final p in projects)
                ChoiceChip(
                  label: Text(p.name),
                  selected: task.projectId == p.id,
                  onSelected: (_) => _repo.updateFields(
                      widget.taskId, TasksCompanion(projectId: Value<String?>(p.id))),
                ),
            ]),
          ),
        ],

        _section('الوصف'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _desc,
            minLines: 2,
            maxLines: 8,
            decoration: const InputDecoration(
                hintText: 'تفاصيل إضافية…', border: OutlineInputBorder()),
          ),
        ),

        _section(subs.isEmpty ? 'المهام الفرعية' : 'المهام الفرعية ($subsDone/${subs.length})'),
        for (final s in subs)
          CheckboxListTile(
            value: s.status == 'done',
            onChanged: (_) => _toggle(s),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(s.title,
                style: s.status == 'done'
                    ? const TextStyle(decoration: TextDecoration.lineThrough)
                    : null),
            secondary: IconButton(
                tooltip: 'حذف',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _repo.softDelete(s.id)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _sub,
            textInputAction: TextInputAction.done,
            onSubmitted: _addSubtask,
            decoration: const InputDecoration(
                hintText: 'أضف مهمة فرعية', prefixIcon: Icon(Icons.add)),
          ),
        ),

        _section('تعتمد على'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, children: [
            for (final d in deps)
              InputChip(
                avatar: Icon(d.status == 'done' ? Icons.check_circle : Icons.lock_outline,
                    size: 16),
                label: Text(d.title),
                onDeleted: () => _repo.removeDependency(widget.taskId, d.id),
              ),
            ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('إضافة'),
                onPressed: _addDependency),
          ]),
        ),
        if (deps.any((d) => d.status != 'done'))
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text('لا يمكن إنجاز هذه المهمة قبل إنجاز المهام المقفلة أعلاه.'),
          ),

        _section('الملاحظات المرتبطة'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, children: [
            for (final n in notes)
              InputChip(
                avatar: const Icon(Icons.description_outlined, size: 16),
                label: Text(n.title.isEmpty ? 'بدون عنوان' : n.title),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => NoteEditorScreen(noteId: n.id))),
                onDeleted: () => _repo.unlinkNote(widget.taskId, n.id),
              ),
            ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('ربط ملاحظة'),
                onPressed: _linkNote),
          ]),
        ),
      ]),
    );
  }
}
