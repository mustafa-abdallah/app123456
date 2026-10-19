/// الروابط الداخلية بصيغة [[عنوان]] أو [[عنوان|نص العرض]].
final _linkRe = RegExp(r'\[\[([^\[\]|\n]+)(?:\|([^\[\]\n]*))?\]\]');

/// عناوين الملاحظات المشار إليها (بدون تكرار، بالترتيب).
List<String> extractLinkTitles(String body) {
  final out = <String>[];
  for (final m in _linkRe.allMatches(body)) {
    final t = m.group(1)!.trim();
    if (t.isNotEmpty && !out.contains(t)) out.add(t);
  }
  return out;
}

const noteScheme = 'note://';

/// يحوّل [[...]] إلى رابط Markdown عادي لأجل المعاينة.
String linksToMarkdown(String body) => body.replaceAllMapped(_linkRe, (m) {
      final target = m.group(1)!.trim();
      final alias = m.group(2)?.trim();
      final label = (alias != null && alias.isNotEmpty) ? alias : target;
      return '[$label]($noteScheme${Uri.encodeComponent(target)})';
    });
