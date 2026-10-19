import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../repositories/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _toast(BuildContext context, String msg) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final text = await ref.read(backupServiceProvider).exportJson();
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        _toast(context,
            'نُسخت البيانات إلى الحافظة (${(text.length / 1024).ceil()} ك.ب). الصقها في مكان آمن.');
      }
    } catch (e) {
      if (context.mounted) _toast(context, 'تعذّر التصدير: $e');
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استيراد نسخة احتياطية'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('تُدمج البيانات مع الموجود، ولا يُحذف شيء. السجل المطابق بالمعرّف نفسه يُحدَّث.'),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            maxLines: 6,
            decoration: const InputDecoration(
                hintText: 'الصق النسخة الاحتياطية هنا', border: OutlineInputBorder()),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.content_paste, size: 18),
              label: const Text('لصق من الحافظة'),
              onPressed: () async {
                final d = await Clipboard.getData(Clipboard.kTextPlain);
                if (d?.text != null) c.text = d!.text!;
              },
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('استيراد')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      final n = await ref.read(backupServiceProvider).importJson(text);
      if (context.mounted) _toast(context, 'تم استيراد $n سجلًا');
    } on FormatException catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('الإعدادات')),
        body: ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('النسخ الاحتياطي', style: Theme.of(context).textTheme.titleSmall),
          ),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('نسخ بياناتك إلى الحافظة'),
            subtitle: const Text('ملاحظات ومهام وعادات وسجلاتها، بصيغة JSON'),
            onTap: () => _export(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('استيراد من نسخة احتياطية'),
            subtitle: const Text('دمج دون حذف الموجود'),
            onTap: () => _import(context, ref),
          ),
        ]),
      );
}
