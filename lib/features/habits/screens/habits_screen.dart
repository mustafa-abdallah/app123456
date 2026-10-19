import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/habit_schedule.dart';
import '../../../core/streak.dart';
import '../../../core/widgets/prompt.dart';
import '../../../database/database.dart';
import '../../../repositories/providers.dart';
import '../providers/habits_providers.dart';
import 'habit_detail_screen.dart';

const _dayLetters = ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'];
const _dayNames = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

enum _Dot { done, partial, excused, missed, off }

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  void _toast(BuildContext context, String m) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _edit(BuildContext context, WidgetRef ref,
      {Habit? habit, int mask = 127}) async {
    final repo = ref.read(habitsRepositoryProvider);
    final d = await showModalBottomSheet<_HabitDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HabitSheet(habit: habit, mask: mask),
    );
    if (d == null) return;
    if (habit == null) {
      await repo.create(d.name,
          daysMask: d.mask, kind: d.kind, target: d.target, unit: d.unit);
      return;
    }
    if (d.name != habit.name) await repo.rename(habit.id, d.name);
    if (d.kind != habit.kind || d.target != habit.targetValue || d.unit != habit.unit) {
      await repo.setGoal(habit.id, kind: d.kind, target: d.target, unit: d.unit);
    }
    if (habit.pausedAt == null && d.mask != mask) await repo.setDays(habit.id, d.mask);
  }

  Future<double?> _askAmount(BuildContext context, Habit h, double current) {
    final c = TextEditingController(text: current > 0 ? formatNumber(current) : '');
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(h.name),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'الكمية',
            suffixText: h.unit,
            helperText: 'الهدف: ${formatNumber(h.targetValue)} ${h.unit ?? ''}'.trim(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 0.0), child: const Text('مسح')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, h.targetValue),
              child: const Text('إكمال الهدف')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, parseNumber(c.text)),
              child: const Text('حفظ')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider);
    final logs = ref.watch(habitLogsProvider).valueOrNull ?? const <HabitLog>[];
    final schedules =
        ref.watch(habitSchedulesProvider).valueOrNull ?? const <String, List<HabitSchedule>>{};
    final repo = ref.read(habitsRepositoryProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final week = [for (var i = 0; i < 7; i++) DateTime(today.year, today.month, today.day - i)];
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref),
        child: const Icon(Icons.add),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('العادات',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Text('اضغط مطولًا على أي يوم لتعيينه إجازة',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
        Expanded(
          child: habits.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('تعذّر تحميل العادات\n$e')),
            data: (list) {
              if (list.isEmpty) {
                return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.local_fire_department_outlined, size: 56, color: scheme.primary),
                  const SizedBox(height: 8),
                  const Text('لا توجد عادات بعد'),
                  const Text('اضغط + لإضافة أول عادة'),
                ]));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final h = list[i];
                  final spans = spansOf(schedules[h.id]);
                  final days = habitDaysFor(logs.where((l) => l.habitId == h.id), h.targetValue);
                  final paused = h.pausedAt != null;
                  final mask = currentMaskOf(spans);
                  final streak = currentStreak(days.done, now,
                      scheduledOn: (d) => scheduledOnDate(spans, d), excused: days.excused);
                  final todayKey = formatDate(today);
                  final todayValue = days.values[todayKey] ?? 0;

                  _Dot stateOf(DateTime d) {
                    final k = formatDate(d);
                    if (days.done.contains(k)) return _Dot.done;
                    if (days.excused.contains(k)) return _Dot.excused;
                    if ((days.partial[k] ?? 0) > 0) return _Dot.partial;
                    return scheduledOnDate(spans, d) ? _Dot.missed : _Dot.off;
                  }

                  final subtitle = StringBuffer(paused
                      ? 'متوقفة مؤقتًا'
                      : mask == 127
                          ? 'كل يوم'
                          : [for (var b = 0; b < 7; b++) if (mask & (1 << b) != 0) _dayLetters[b]]
                              .join(' '));
                  if (h.kind != 'check') {
                    subtitle.write(
                        ' · اليوم ${formatNumber(todayValue)}/${formatNumber(h.targetValue)} ${h.unit ?? ''}'
                            .trimRight());
                  }

                  return Opacity(
                    opacity: paused ? 0.6 : 1,
                    child: Material(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => HabitDetailScreen(habitId: h.id))),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
                          child: Column(children: [
                            Row(children: [
                              Expanded(
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(h.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(fontWeight: FontWeight.w600)),
                                      Text(subtitle.toString(),
                                          style: Theme.of(context).textTheme.bodySmall),
                                    ]),
                              ),
                              if (streak > 0) ...[
                                const Icon(Icons.local_fire_department,
                                    size: 18, color: Colors.orange),
                                const SizedBox(width: 2),
                                Text('$streak'),
                              ],
                              PopupMenuButton<String>(
                                onSelected: (v) async {
                                  switch (v) {
                                    case 'edit':
                                      await _edit(context, ref, habit: h, mask: mask);
                                    case 'pause':
                                      await repo.pause(h.id);
                                    case 'resume':
                                      await repo.resume(h.id);
                                    case 'delete':
                                      final ok = await confirm(context,
                                          title: 'حذف العادة؟',
                                          message: 'ستختفي العادة من القائمة.',
                                          action: 'حذف');
                                      if (ok) await repo.softDelete(h.id);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                                  PopupMenuItem(
                                      value: paused ? 'resume' : 'pause',
                                      child: Text(paused ? 'استئناف' : 'إيقاف مؤقت')),
                                  const PopupMenuItem(value: 'delete', child: Text('حذف')),
                                ],
                              ),
                            ]),
                            if (h.kind != 'check') ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(0, 4, 8, 0),
                                child: LinearProgressIndicator(
                                  value: (todayValue / (h.targetValue <= 0 ? 1 : h.targetValue))
                                      .clamp(0.0, 1.0)
                                      .toDouble(),
                                  minHeight: 6,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  for (final d in week)
                                    _DayDot(
                                      letter: _dayLetters[d.weekday - 1],
                                      state: stateOf(d),
                                      isToday: d == today,
                                      onTap: paused
                                          ? null
                                          : () async {
                                              final key = formatDate(d);
                                              if (h.kind == 'check') {
                                                await repo.toggleDay(h.id, key);
                                                return;
                                              }
                                              final v = await _askAmount(
                                                  context, h, days.values[key] ?? 0);
                                              if (v != null) await repo.logValue(h.id, key, v);
                                            },
                                      onLongPress: paused
                                          ? null
                                          : () async {
                                              final key = formatDate(d);
                                              final on = !days.excused.contains(key);
                                              await repo.setExcused(h.id, key, on);
                                              if (context.mounted) {
                                                _toast(context,
                                                    on ? 'عُيّن اليوم إجازة' : 'أُلغيت الإجازة');
                                              }
                                            },
                                    ),
                                ],
                              ),
                            ),
                          ]),
                        ),
                      ),
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

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.letter,
    required this.state,
    required this.isToday,
    required this.onTap,
    required this.onLongPress,
  });
  final String letter;
  final _Dot state;
  final bool isToday;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color? fill;
    Widget? icon;
    Color border = scheme.onSurface.withAlpha(70);
    switch (state) {
      case _Dot.done:
        fill = scheme.primary;
        border = scheme.primary;
        icon = Icon(Icons.check, size: 18, color: scheme.onPrimary);
      case _Dot.partial:
        fill = scheme.primary.withAlpha(70);
        border = scheme.primary;
        icon = Icon(Icons.timelapse, size: 16, color: scheme.primary);
      case _Dot.excused:
        fill = scheme.secondary.withAlpha(60);
        border = scheme.secondary;
        icon = Icon(Icons.beach_access_outlined, size: 16, color: scheme.secondary);
      case _Dot.missed:
        break;
      case _Dot.off:
        fill = scheme.onSurface.withAlpha(15);
        border = Colors.transparent;
    }
    if (isToday && state != _Dot.done) border = scheme.primary;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Column(children: [
        Text(letter, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill,
            border: Border.all(color: border, width: isToday ? 2 : 1.2),
          ),
          child: icon,
        ),
      ]),
    );
  }
}

class _HabitDraft {
  const _HabitDraft({
    required this.name,
    required this.kind,
    required this.target,
    required this.unit,
    required this.mask,
  });
  final String name;
  final String kind;
  final double target;
  final String? unit;
  final int mask;
}

/// إنشاء عادة أو تعديلها: الاسم، النوع (نعم/لا، عدد، مدة)، الهدف، وأيام الأسبوع.
class _HabitSheet extends StatefulWidget {
  const _HabitSheet({required this.habit, required this.mask});
  final Habit? habit;
  final int mask;

  @override
  State<_HabitSheet> createState() => _HabitSheetState();
}

class _HabitSheetState extends State<_HabitSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.habit?.name ?? '');
  late final TextEditingController _target = TextEditingController(
      text: (widget.habit == null || widget.habit!.kind == 'check')
          ? ''
          : formatNumber(widget.habit!.targetValue));
  late final TextEditingController _unit =
      TextEditingController(text: widget.habit?.unit ?? '');
  late String _kind = widget.habit?.kind ?? 'check';
  late int _mask = widget.mask;
  String? _error;

  bool get _paused => widget.habit?.pausedAt != null;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _unit.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'اكتب اسم العادة');
      return;
    }
    var target = 1.0;
    String? unit;
    if (_kind != 'check') {
      final t = parseNumber(_target.text);
      if (t == null || t <= 0) {
        setState(() => _error = 'اكتب هدفًا أكبر من صفر');
        return;
      }
      target = t;
      final u = _unit.text.trim();
      unit = u.isEmpty ? (_kind == 'duration' ? 'دقيقة' : null) : u;
    }
    if (_mask == 0) {
      setState(() => _error = 'اختر يومًا واحدًا على الأقل');
      return;
    }
    Navigator.pop(
        context,
        _HabitDraft(name: name, kind: _kind, target: target, unit: unit, mask: _mask));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.habit == null ? 'عادة جديدة' : 'تعديل العادة',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: widget.habit == null,
            decoration: const InputDecoration(labelText: 'اسم العادة'),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'check', label: Text('نعم/لا')),
              ButtonSegment(value: 'count', label: Text('عدد')),
              ButtonSegment(value: 'duration', label: Text('مدة')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          if (_kind != 'check') ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _target,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'الهدف اليومي'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _unit,
                  decoration: InputDecoration(
                      labelText: 'الوحدة',
                      hintText: _kind == 'duration' ? 'دقيقة' : 'صفحة، كوب…'),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 16),
          Text('أيام العادة', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (var i = 0; i < 7; i++)
              FilterChip(
                label: Text(_dayNames[i]),
                selected: _mask & (1 << i) != 0,
                onSelected: _paused ? null : (_) => setState(() => _mask ^= 1 << i),
              ),
          ]),
          if (_paused)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('لا تتغير الأيام أثناء الإيقاف المؤقت. استأنف العادة أولًا.'),
            ),
          if (widget.habit != null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('تغيير الأيام يسري من اليوم فصاعدًا ولا يمسّ سجلّك السابق.'),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _save, child: const Text('حفظ')),
          ),
        ]),
      ),
    );
  }
}
