import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/currency_info.dart';

class MoneyCard extends StatelessWidget {
  const MoneyCard({
    required this.fieldKey,
    required this.currencyButtonKey,
    required this.label,
    required this.currency,
    required this.controller,
    required this.isActive,
    required this.onChanged,
    required this.onTap,
    required this.onChooseCurrency,
    this.loading = false,
    super.key,
  });

  final Key fieldKey;
  final Key currencyButtonKey;
  final String label;
  final CurrencyInfo currency;
  final TextEditingController controller;
  final bool isActive;
  final bool loading;
  final ValueChanged<String> onChanged;
  final VoidCallback onTap;
  final VoidCallback onChooseCurrency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final outline = isActive
        ? colors.onSurface
        : colors.outline.withValues(alpha: 0.5);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.fromLTRB(21, 18, 21, 16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colors.surfaceContainerHighest.withValues(alpha: 0.25),
          colors.surface,
        ),
        border: Border.all(color: outline, width: isActive ? 1.5 : 1),
        borderRadius: BorderRadius.circular(22),
        boxShadow: isActive
            ? [BoxShadow(color: colors.onSurface, offset: const Offset(3, 3))]
            : null,
      ),
      transform: Matrix4.translationValues(
        isActive ? -1.5 : 0,
        isActive ? -1.5 : 0,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.58),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
              InkWell(
                key: currencyButtonKey,
                onTap: onChooseCurrency,
                borderRadius: BorderRadius.circular(11),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(currency.flag, style: const TextStyle(fontSize: 17)),
                      const SizedBox(width: 7),
                      Text(
                        currency.code,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: colors.onSurface.withValues(alpha: 0.56),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                currency.symbol,
                style: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.56),
                  fontFamily: 'Fraunces',
                  fontSize: 27,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: fieldKey,
                  controller: controller,
                  onTap: onTap,
                  onChanged: onChanged,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                  ],
                  style: TextStyle(
                    color: colors.onSurface,
                    fontFamily: 'Fraunces',
                    fontSize: 45,
                    height: 1.05,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -2,
                  ),
                  decoration: InputDecoration(
                    hintText: loading ? '···' : '0',
                    hintStyle: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.24),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            currency.name,
            style: TextStyle(
              color: colors.onSurface.withValues(alpha: 0.58),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
