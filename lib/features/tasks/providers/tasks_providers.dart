import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../database/database.dart';
import '../../../repositories/providers.dart';
import '../../../repositories/tasks_repository.dart';

final taskViewProvider = StateProvider<TaskView>((ref) => TaskView.active);

/// المهام حسب التبويب المختار (نشطة / منجزة).
final tasksProvider = StreamProvider.autoDispose<List<Task>>((ref) =>
    ref.watch(tasksRepositoryProvider).watch(ref.watch(taskViewProvider)));

/// المهام النشطة دائمًا (تستخدمها لوحة التحكم).
final activeTasksProvider = StreamProvider.autoDispose<List<Task>>(
    (ref) => ref.watch(tasksRepositoryProvider).watch(TaskView.active));
