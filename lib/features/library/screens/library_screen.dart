import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../repositories/notes_repository.dart';
import '../../notes/providers/notes_providers.dart';
import 'folders_screen.dart';
import 'tags_screen.dart';

/// بلاطات ملونة للتنظيم: كل الملاحظات، المجلدات، الوسوم، المحذوفات.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  void _setFilter(BuildContext context, WidgetRef ref, NotesFilter f) {
    ref.read(notesFilterProvider.notifier).state = f;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiles = <_Tile>[
      _Tile(Icons.notes, 'كل الملاحظات', const Color(0xFF7CB342),
          () => _setFilter(context, ref, const NotesFilter())),
      _Tile(Icons.folder_copy_outlined, 'المجلدات', const Color(0xFFC0CA33), () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FoldersScreen()))),
      _Tile(Icons.tag, 'الوسوم', const Color(0xFF42A5F5), () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TagsScreen()))),
      _Tile(Icons.delete_outline, 'المحذوفات', const Color(0xFFEF5350),
          () => _setFilter(context, ref, const NotesFilter(trash: true, label: 'المحذوفات'))),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('المكتبة')),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        children: tiles.map((t) => t.build(context)).toList(),
      ),
    );
  }
}

class _Tile {
  _Tile(this.icon, this.label, this.color, this.onTap);
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: color.withAlpha(dark ? 45 : 80),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 10),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
        ]),
      ),
    );
  }
}
