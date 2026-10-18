import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/widgets/prompt.dart';
import '../../../core/wiki_links.dart';
import '../../../database/database.dart';
import '../../../repositories/notes_repository.dart';
import '../../../repositories/providers.dart';

enum _Save { saved, dirty, saving, failed }

class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, required this.noteId});
  final String noteId;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final NotesRepository _repo;
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _bodyFocus = FocusNode();
  Timer? _debounce;

  bool _loaded = false;
  bool _preview = false;
  String _lastTitle = '';
  String _lastBody = '';
  List<Tag> _tags = [];
  _Save _state = _Save.saved;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(notesRepositoryProvider);
    _load();
  }

  Future<void> _load() async {
    final note = await _repo.getById(widget.noteId);
    final tags = await _repo.tagsFor(widget.noteId);
    if (!mounted) return;
    _title.text = note?.title ?? '';
    _body.text = note?.bodyMd ?? '';
    _lastTitle = _title.text;
    _lastBody = _body.text;
    _title.addListener(_onChanged);
    _body.addListener(_onChanged);
    setState(() {
      _tags = tags;
      _loaded = true;
    });
  }

  bool get _changed => _title.text != _lastTitle || _body.text != _lastBody;

  void _onChanged() {
    if (!_loaded || !_changed) return;
    if (_state != _Save.dirty) setState(() => _state = _Save.dirty);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _autosave);
  }

  /// لا تُحدَّث _lastTitle/_lastBody إلا بعد نجاح الكتابة فعلًا.
  Future<bool> _persist() async {
    final t = _title.text, b = _body.text;
    try {
      await _repo.save(widget.noteId, title: t, body: b);
      _lastTitle = t;
      _lastBody = b;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _autosave() async {
    if (!mounted) return;
    setState(() => _state = _Save.saving);
    final ok = await _persist();
    if (!mounted) return;
    setState(() => _state = !ok ? _Save.failed : (_changed ? _Save.dirty : _Save.saved));
    if (ok && _changed) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 800), _autosave);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_loaded) {
      final t = _title.text, b = _body.text;
      if (t.isEmpty && b.isEmpty) {
        unawaited(_repo.deleteIfEmpty(widget.noteId));
      } else if (t != _lastTitle || b != _lastBody) {
        unawaited(_repo.save(widget.noteId, title: t, body: b));
      }
    }
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  // ---------- أدوات Markdown ----------

  void _setBody(String text, TextSelection sel) {
    _body.value = TextEditingValue(text: text, selection: sel);
    _bodyFocus.requestFocus();
  }

  void _wrap(String l, String r, {String placeholder = ''}) {
    final text = _body.text;
    var sel = _body.selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: text.length);
    final inner = sel.textInside(text).isEmpty ? placeholder : sel.textInside(text);
    final out = text.replaceRange(sel.start, sel.end, '$l$inner$r');
    _setBody(out, TextSelection(
        baseOffset: sel.start + l.length,
        extentOffset: sel.start + l.length + inner.length));
  }

  void _linePrefix(String p) {
    final text = _body.text;
    var sel = _body.selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: text.length);
    final lineStart = sel.start == 0 ? 0 : text.lastIndexOf('\n', sel.start - 1) + 1;
    final out = text.replaceRange(lineStart, lineStart, p);
    _setBody(out, TextSelection(
        baseOffset: sel.start + p.length, extentOffset: sel.end + p.length));
  }

  void _insert(String s) {
    final text = _body.text;
    var sel = _body.selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: text.length);
    final out = text.replaceRange(sel.start, sel.end, s);
    _setBody(out, TextSelection.collapsed(offset: sel.start + s.length));
  }

  // ---------- الوسوم والمجلدات ----------

  Future<void> _reloadTags() async {
    final tags = await _repo.tagsFor(widget.noteId);
    if (mounted) setState(() => _tags = tags);
  }

  Future<void> _addTag() async {
    final name = await promptText(context, title: 'وسم جديد', hint: 'مثال: فقه');
    if (name == null) return;
    await _repo.addTag(widget.noteId, name);
    await _reloadTags();
  }

  Future<void> _moveToFolder() async {
    final folders = await ref.read(foldersRepositoryProvider).allWithPath();
    if (!mounted) return;
    if (folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أنشئ مجلدًا أولًا من المكتبة')));
      return;
    }
    // '' = بدون مجلد، null = إلغاء
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('نقل إلى مجلد'),
        children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, ''), child: const Text('بدون مجلد')),
          for (final f in folders)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, f.folder.id), child: Text(f.path)),
        ],
      ),
    );
    if (choice == null) return;
    await _repo.moveToFolder(widget.noteId, choice.isEmpty ? null : choice);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم النقل')));
    }
  }

  // ---------- الروابط الداخلية ----------

  Future<void> _openNote(String id) async {
    if (_changed) await _persist();
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: id)));
  }

  /// يفتح الملاحظة بعنوانها، وينشئها إن لم تكن موجودة (مثل Obsidian).
  Future<void> _openLink(String title) async {
    final existing = await _repo.findByTitle(title);
    final id = existing?.id ?? await _repo.create(title: title.trim());
    await _openNote(id);
  }

  Future<void> _showLinks() async {
    if (_changed) await _persist();
    final back = await _repo.backlinks(widget.noteId);
    final out = extractLinkTitles(_body.text);
    final exists = <String, bool>{
      for (final t in out) t: await _repo.findByTitle(t) != null,
    };
    if (!mounted) return;
    final style = Theme.of(context).textTheme.titleSmall;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (c, scroll) => ListView(controller: scroll, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('الروابط الواردة (${back.length})', style: style)),
          if (_title.text.trim().isEmpty)
            const ListTile(title: Text('أعطِ الملاحظة عنوانًا لتظهر الروابط الواردة'))
          else if (back.isEmpty)
            const ListTile(title: Text('لا توجد ملاحظات تشير إلى هذه الملاحظة'))
          else
            for (final b in back)
              ListTile(
                leading: const Icon(Icons.subdirectory_arrow_left),
                title: Text(b.title.isEmpty ? 'بدون عنوان' : b.title),
                onTap: () {
                  Navigator.pop(ctx);
                  _openNote(b.id);
                },
              ),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('الروابط الصادرة (${out.length})', style: style)),
          if (out.isEmpty) const ListTile(title: Text('لا روابط [[ ]] في هذه الملاحظة')),
          for (final t in out)
            ListTile(
              leading: Icon(exists[t]! ? Icons.link : Icons.add_link),
              title: Text(t),
              subtitle: exists[t]! ? null : const Text('غير موجودة — اضغط لإنشائها'),
              onTap: () {
                Navigator.pop(ctx);
                _openLink(t);
              },
            ),
        ]),
      ),
    );
  }

  // ---------- سجل التعديلات ----------

  Future<void> _showHistory() async {
    final versions = await _repo.versions(widget.noteId);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        if (versions.isEmpty) {
          return const SizedBox(
              height: 160, child: Center(child: Text('لا توجد نسخ سابقة بعد')));
        }
        return ListView.builder(
          itemCount: versions.length,
          itemBuilder: (c, i) {
            final v = versions[i];
            final preview = v.bodyMd.trim();
            return ListTile(
              title: Text(formatDateTime(v.createdAt)),
              subtitle: Text(preview.isEmpty ? '(فارغة)' : preview,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(ctx);
                _confirmRestore(v);
              },
            );
          },
        );
      },
    );
  }

  Future<void> _confirmRestore(NoteVersion v) async {
    final ok = await confirm(context,
        title: 'استرجاع هذه النسخة؟',
        message: 'سيُحفظ نص الملاحظة الحالي في السجل قبل الاسترجاع.',
        action: 'استرجاع');
    if (!ok || !mounted) return;
    await _repo.snapshot(widget.noteId, title: _title.text, body: _body.text);
    _title.text = v.title;
    _body.text = v.bodyMd;
  }

  // ---------- الواجهة ----------

  Widget _status(BuildContext context) {
    final (text, color) = switch (_state) {
      _Save.saved => ('تم الحفظ', null),
      _Save.saving => ('جارٍ الحفظ…', null),
      _Save.dirty => ('تعديلات غير محفوظة', null),
      _Save.failed => ('تعذّر الحفظ', Colors.redAccent),
    };
    return Text(text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color));
  }

  Widget _tagsRow() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Wrap(spacing: 6, runSpacing: 0, children: [
            for (final t in _tags)
              InputChip(
                label: Text('#${t.name}'),
                visualDensity: VisualDensity.compact,
                onDeleted: () async {
                  await _repo.removeTag(widget.noteId, t.id);
                  await _reloadTags();
                },
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('وسم'),
              visualDensity: VisualDensity.compact,
              onPressed: _addTag,
            ),
          ]),
        ),
      );

  Widget _toolbar(BuildContext context) {
    Widget icon(IconData i, VoidCallback f, String tip) =>
        IconButton(icon: Icon(i), tooltip: tip, onPressed: f);
    Widget label(String t, VoidCallback f) => TextButton(
        onPressed: f,
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)));

    return Container(
      color: Theme.of(context).colorScheme.surface,
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          icon(Icons.format_bold, () => _wrap('**', '**', placeholder: 'نص'), 'عريض'),
          icon(Icons.format_italic, () => _wrap('*', '*', placeholder: 'نص'), 'مائل'),
          icon(Icons.code, () => _wrap('`', '`', placeholder: 'كود'), 'كود'),
          label('H1', () => _linePrefix('# ')),
          label('H2', () => _linePrefix('## ')),
          label('H3', () => _linePrefix('### ')),
          icon(Icons.format_list_bulleted, () => _linePrefix('- '), 'قائمة'),
          icon(Icons.format_list_numbered, () => _linePrefix('1. '), 'قائمة مرقمة'),
          icon(Icons.check_box_outlined, () => _linePrefix('- [ ] '), 'مربع اختيار'),
          icon(Icons.format_quote, () => _linePrefix('> '), 'اقتباس'),
          icon(Icons.link, () => _wrap('[', '](https://)', placeholder: 'نص الرابط'), 'رابط'),
          label('[[ ]]', () => _wrap('[[', ']]', placeholder: 'اسم الملاحظة')),
          icon(Icons.event, () => _insert(formatDate(DateTime.now())), 'تاريخ اليوم'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _status(context),
        actions: [
          IconButton(
            tooltip: _preview ? 'تحرير' : 'معاينة',
            icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined),
            onPressed: _loaded ? () => setState(() => _preview = !_preview) : null,
          ),
          PopupMenuButton<String>(
            enabled: _loaded,
            onSelected: (v) {
              switch (v) {
                case 'links':
                  _showLinks();
                case 'history':
                  _showHistory();
                case 'move':
                  _moveToFolder();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'links', child: Text('الروابط')),
              PopupMenuItem(value: 'history', child: Text('سجل التعديلات')),
              PopupMenuItem(value: 'move', child: Text('نقل إلى مجلد')),
            ],
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _title,
                  readOnly: _preview,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _bodyFocus.requestFocus(),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                      hintText: 'العنوان', border: InputBorder.none),
                ),
              ),
              _tagsRow(),
              Expanded(
                child: _preview
                    ? Markdown(
                        data: linksToMarkdown(_body.text),
                        onTapLink: (text, href, title) {
                          if (href != null && href.startsWith(noteScheme)) {
                            _openLink(Uri.decodeComponent(href.substring(noteScheme.length)));
                          }
                        },
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: _body,
                          focusNode: _bodyFocus,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          keyboardType: TextInputType.multiline,
                          decoration: const InputDecoration(
                              hintText: 'اكتب هنا… (يدعم Markdown)',
                              border: InputBorder.none),
                        ),
                      ),
              ),
              if (!_preview) _toolbar(context),
            ]),
    );
  }
}
