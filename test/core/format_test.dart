import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_app/core/format.dart';

void main() {
  test('قراءة الأرقام: عربية وغربية وفاصلة عربية', () {
    expect(parseNumber('12'), 12);
    expect(parseNumber('٣٫٥'), 3.5);
    expect(parseNumber(' ٢٠ '), 20);
    expect(parseNumber('2,5'), 2.5);
    expect(parseNumber('abc'), isNull);
    expect(parseNumber(''), isNull);
  });

  test('تنسيق الأرقام بلا أصفار زائدة', () {
    expect(formatNumber(10.0), '10');
    expect(formatNumber(2.5), '2.5');
  });
}
