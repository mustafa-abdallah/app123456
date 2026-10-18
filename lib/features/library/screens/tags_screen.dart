import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../repositories/notes_repository.dart';
import '../../notes/providers/notes_providers.dart';

class TagsScreen extends ConsumerWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagCountsProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('الوسوم')),
      body: tags.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('تعذّر تحميل الوسوم\n$e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('لا توجد وسوم بعد — أضفها من داخل أي ملاحظة'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final t = list[i];
              return Material(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(20),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  leading: Icon(Icons.tag, color: scheme.secondary),
                  title: Text(t.name),
                  trailing: Text('${t.count}'),
                  onTap: () {
                    ref.read(notesFilterProvider.notifier).state =
                        NotesFilter(tagId: t.id, label: '#${t.name}');
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
