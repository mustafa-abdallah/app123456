String _two(int n) => n.toString().padLeft(2, '0');

String formatDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String formatDateTime(DateTime d) =>
    '${d.year}/${_two(d.month)}/${_two(d.day)}  ${_two(d.hour)}:${_two(d.minute)}';

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// يقرأ رقمًا من نص المستخدم (يقبل الأرقام العربية والفاصلة العربية). null إن لم يكن رقمًا.
double? parseNumber(String input) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in input.trim().split('')) {
    final i = arabic.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (ch == '٫' || ch == '،' || ch == ',') {
      b.write('.');
    } else {
      b.write(ch);
    }
  }
  return double.tryParse(b.toString());
}

/// 10.0 -> "10" ، 2.5 -> "2.5"
String formatNumber(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
