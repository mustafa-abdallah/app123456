import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/widgets/prompt.dart';
import '../../../repositories/providers.dart';
import '../../../services/backup_service.dart';
import '../providers/settings_providers.dart';

const _tableLabels = {
  'notes': 'ملاحظات',
  'tasks': 'مهام',
  'habits': 'عادات',
  'habitLogs': 'سجلات العادات',
  'folders': 'مجلدات',
  'tags': 'وسوم',
  'projects': 'تصنيفات',
};

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _toast(BuildContext context, String msg) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(msg)));

  static String _fileName() {
    final n = DateTime.now();
    String t(int v) => v.toString().padLeft(2, '0');
    return 'knowledge-backup-${n.year}-${t(n.month)}-${t(n.day)}-${t(n.hour)}${t(n.minute)}.json';
  }

  // ---------- التصدير ----------

  Future<void> _exportFile(BuildContext context, WidgetRef ref) async {
    try {
      final text = await ref.read(backupServiceProvider).exportJson();
      final bytes = Uint8List.fromList(utf8.encode(text));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'اختر مكان حفظ النسخة الاحتياطية',
        fileName: _fileName(),
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (path == null) {
        if (context.mounted) _toast(context, 'لم تُحفظ النسخة');
        return;
      }
      await ref.read(settingsRepositoryProvider).markExported();
      if (context.mounted) {
        _toast(context, 'حُفظت النسخة (${(bytes.length / 1024).ceil()} ك.ب)');
      }
    } catch (e) {
      if (context.mounted) _toast(context, 'تعذّر الحفظ: $e');
    }
  }

  Future<void> _exportClipboard(BuildContext context, WidgetRef ref) async {
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

  // ---------- الاستعادة ----------

  /// يفحص النسخة ويعرض ملخصها، ثم يستعيدها بعد اختيار المستخدم (دمج أو استبدال).
  Future<void> _inspectAndRestore(BuildContext context, WidgetRef ref, String text) async {
    final svc = ref.read(backupServiceProvider);
    final BackupInfo info;
    try {
      info = svc.inspect(text);
    } on FormatException catch (e) {
      _toast(context, e.message);
      return;
    }
    if (!context.mounted) return;

    final lines = <String>[
      'التاريخ: ${info.exportedAt == null ? 'غير معروف' : formatDateTime(info.exportedAt!)}',
      info.verified
          ? 'سلامة الملف: تم التحقق ✓'
          : 'سلامة الملف: نسخة قديمة بلا مجموع اختباري',
      for (final e in _tableLabels.entries)
        if ((info.counts[e.key] ?? 0) > 0) '${e.value}: ${info.counts[e.key]}',
    ];
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة نسخة احتياطية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in lines) Text(l),
            const SizedBox(height: 12),
            const Text('دمج: يضيف ما في النسخة ولا يحذف شيئًا.\n'
                'استبدال: يمسح كل ما في التطبيق الآن ويضع محتوى النسخة.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'replace'), child: const Text('استبدال')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'merge'), child: const Text('دمج')),
        ],
      ),
    );
    if (mode == null || !context.mounted) return;

    if (mode == 'replace') {
      final ok = await confirm(context,
          title: 'استبدال كل البيانات؟',
          message: 'سيُحذف كل ما في التطبيق الآن ويُستبدل بمحتوى النسخة. لا يمكن التراجع.',
          action: 'استبدال');
      if (!ok || !context.mounted) return;
    }
    try {
      final n = await svc.importJson(text, replace: mode == 'replace');
      if (context.mounted) _toast(context, 'تمت الاستعادة: $n سجلًا');
    } on FormatException catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }

  Future<void> _importFile(BuildContext context, WidgetRef ref) async {
    final String text;
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      final bytes = r?.files.single.bytes;
      if (bytes == null) return;
      text = utf8.decode(bytes);
    } on FormatException {
      if (context.mounted) _toast(context, 'الملف ليس نسخة احتياطية نصية صالحة');
      return;
    } catch (e) {
      if (context.mounted) _toast(context, 'تعذّرت قراءة الملف: $e');
      return;
    }
    if (context.mounted) await _inspectAndRestore(context, ref, text);
  }

  Future<void> _importClipboard(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استيراد من نص'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
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
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('متابعة')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    await _inspectAndRestore(context, ref, text);
  }

  // ---------- سلامة قاعدة البيانات ----------

  Future<void> _checkIntegrity(BuildContext context, WidgetRef ref) async {
    try {
      final r = await ref.read(databaseProvider).integrityCheck();
      if (!context.mounted) return;
      _toast(context, r == 'ok' ? 'قاعدة البيانات سليمة ✓' : 'رُصدت مشكلة: $r');
    } catch (e) {
      if (context.mounted) _toast(context, 'تعذّر الفحص: $e');
    }
  }

  Future<void> _rebuildIndex(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(databaseProvider).rebuildSearchIndex();
      if (context.mounted) _toast(context, 'أُعيد بناء فهرس البحث');
    } catch (e) {
      if (context.mounted) _toast(context, 'تعذّرت إعادة البناء: $e');
    }
  }

  Widget _header(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(t, style: Theme.of(context).textTheme.titleSmall),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastBackupProvider);
    final lastText = last.when(
      data: (d) => d == null ? 'لم تُؤخذ نسخة بعد' : formatDateTime(d),
      loading: () => '…',
      error: (_, __) => 'غير معروف',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(children: [
        _header(context, 'النسخ الاحتياطي'),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('آخر نسخة احتياطية'),
          subtitle: Text(lastText),
        ),
        ListTile(
          leading: const Icon(Icons.save_alt),
          title: const Text('حفظ نسخة احتياطية في ملف'),
          subtitle: const Text('اختر مكانًا آمنًا: التنزيلات أو Google Drive'),
          onTap: () => _exportFile(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.folder_open),
          title: const Text('استعادة من ملف'),
          subtitle: const Text('يُفحص الملف ويُعرض ملخصه قبل أي تغيير'),
          onTap: () => _importFile(context, ref),
        ),
        ExpansionTile(
          leading: const Icon(Icons.content_copy_outlined),
          title: const Text('عبر الحافظة (للبيانات الصغيرة)'),
          children: [
            ListTile(
              title: const Text('نسخ البيانات إلى الحافظة'),
              onTap: () => _exportClipboard(context, ref),
            ),
            ListTile(
              title: const Text('استعادة من نص ملصوق'),
              onTap: () => _importClipboard(context, ref),
            ),
          ],
        ),
        _header(context, 'سلامة البيانات'),
        ListTile(
          leading: const Icon(Icons.verified_outlined),
          title: const Text('فحص قاعدة البيانات'),
          onTap: () => _checkIntegrity(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.manage_search),
          title: const Text('إعادة بناء فهرس البحث'),
          subtitle: const Text('إن بدا البحث ناقصًا أو غير دقيق'),
          onTap: () => _rebuildIndex(context, ref),
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'بياناتك محفوظة على هذا الجهاز فقط. حذف التطبيق أو مسح بياناته يفقدها '
            'نهائيًا ما لم تحتفظ بنسخة احتياطية خارج الجهاز.',
          ),
        ),
      ]),
    );
  }
}
