import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../database/database.dart';
import '../../../repositories/providers.dart';
import '../../../repositories/tasks_repository.dart';

final taskViewProvider = StateProvider<TaskView>((ref) => TaskView.active);

/// null = كل الأيام.
final taskDayFilterProvider = StateProvider<DateTime?>((ref) => null);

/// null = كل التصنيفات.
final taskProjectFilterProvider = StateProvider<String?>((ref) => null);

/// المهام حسب التبويب واليوم والتصنيف المختارة.
final tasksProvider = StreamProvider.autoDispose<List<Task>>((ref) {
  return ref.watch(tasksRepositoryProvider).watch(
        ref.watch(taskViewProvider),
        projectId: ref.watch(taskProjectFilterProvider),
        day: ref.watch(taskDayFilterProvider),
      );
});

/// المهام النشطة دائمًا (تستخدمها لوحة التحكم).
final activeTasksProvider = StreamProvider.autoDispose<List<Task>>(
    (ref) => ref.watch(tasksRepositoryProvider).watch(TaskView.active));

final projectsProvider = StreamProvider.autoDispose<List<Project>>(
    (ref) => ref.watch(projectsRepositoryProvider).watchActive());

/// مهمة واحدة (تتحدث فور أي تعديل).
final taskProvider = StreamProvider.autoDispose.family<Task?, String>(
    (ref, id) => ref.watch(tasksRepositoryProvider).watchOne(id));

/// المهام الفرعية لمهمة.
final subtasksProvider = StreamProvider.autoDispose.family<List<Task>, String>(
    (ref, id) => ref.watch(tasksRepositoryProvider).watchSubtasks(id));

/// المهام التي تعتمد عليها مهمة.
final taskDepsProvider = StreamProvider.autoDispose.family<List<Task>, String>(
    (ref, id) => ref.watch(tasksRepositoryProvider).watchDependencies(id));

/// الملاحظات المرتبطة بمهمة.
final taskNotesProvider = StreamProvider.autoDispose.family<List<Note>, String>(
    (ref, id) => ref.watch(tasksRepositoryProvider).watchNotes(id));
