import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import 'folders_repository.dart';
import 'habits_repository.dart';
import 'notes_repository.dart';
import 'tasks_repository.dart';

/// تُمرَّر قاعدة البيانات من main عبر overrideWithValue.
final databaseProvider = Provider<AppDatabase>(
    (ref) => throw UnimplementedError('databaseProvider must be overridden'));

final notesRepositoryProvider =
    Provider<NotesRepository>((ref) => NotesRepository(ref.watch(databaseProvider)));

final foldersRepositoryProvider =
    Provider<FoldersRepository>((ref) => FoldersRepository(ref.watch(databaseProvider)));

final tasksRepositoryProvider =
    Provider<TasksRepository>((ref) => TasksRepository(ref.watch(databaseProvider)));

final habitsRepositoryProvider =
    Provider<HabitsRepository>((ref) => HabitsRepository(ref.watch(databaseProvider)));
