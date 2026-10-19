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
