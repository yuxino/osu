import 'package:intl/intl.dart';

double? parseAmount(String value) {
  final normalized = value.replaceAll(',', '').trim();
  if (normalized.isEmpty) return null;

  final amount = double.tryParse(normalized);
  if (amount == null || !amount.isFinite || amount < 0) return null;
  return amount;
}

String sanitizeAmountInput(String value) {
  final cleaned = value.replaceAll(RegExp(r'[^\d.]'), '');
  final parts = cleaned.split('.');
  final whole = parts.first;
  final fraction = parts.skip(1).join();

  if (cleaned.startsWith('.')) return '0.$fraction';
  return parts.length > 1 ? '$whole.$fraction' : whole;
}

String formatAmount(double? amount, String currencyCode) {
  if (amount == null || !amount.isFinite) return '';
  final pattern = switch (currencyCode) {
    'JPY' || 'KRW' => '#,##0',
    _ => '#,##0.####',
  };
  return NumberFormat(pattern, 'en_US').format(amount);
}

String formatRate(double rate) {
  final pattern = rate < 0.01 ? '0.000000' : '0.0000';
  return NumberFormat(pattern, 'en_US').format(rate);
}
