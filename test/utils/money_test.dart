import 'package:flutter_test/flutter_test.dart';
import 'package:osu/utils/money.dart';

void main() {
  group('money helpers', () {
    test('parses grouped decimal values', () {
      expect(parseAmount('1,234.50'), 1234.5);
      expect(parseAmount(''), isNull);
      expect(parseAmount('-1'), isNull);
    });

    test('sanitizes pasted currency values', () {
      expect(sanitizeAmountInput(r'$1,200.50'), '1200.50');
      expect(sanitizeAmountInput('.5'), '0.5');
      expect(sanitizeAmountInput('1.2.3'), '1.23');
    });

    test('formats values with sensible fraction digits', () {
      expect(formatAmount(1234.567, 'USD'), '1,234.567');
      expect(formatAmount(1234.567, 'JPY'), '1,235');
      expect(formatRate(0.14779), '0.1478');
    });
  });
}
