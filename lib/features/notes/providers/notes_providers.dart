import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../database/database.dart';
import '../../../repositories/notes_repository.dart';
import '../../../repositories/providers.dart';

final notesQueryProvider = StateProvider<String>((ref) => '');
final notesFilterProvider = StateProvider<NotesFilter>((ref) => const NotesFilter());

/// الملاحظات حسب المرشّح، أو نتائج البحث عند وجود نص في خانة البحث.
final visibleNotesProvider = StreamProvider.autoDispose<List<Note>>((ref) {
  final repo = ref.watch(notesRepositoryProvider);
  final q = ref.watch(notesQueryProvider).trim();
  if (q.isNotEmpty) return Stream.fromFuture(repo.search(q));
  return repo.watch(ref.watch(notesFilterProvider));
});

final folderChildrenProvider =
    StreamProvider.autoDispose.family<List<Folder>, String?>((ref, parentId) =>
        ref.watch(foldersRepositoryProvider).watchChildren(parentId));

final tagCountsProvider = FutureProvider.autoDispose<List<TagCount>>(
    (ref) => ref.watch(notesRepositoryProvider).tagsWithCounts());
