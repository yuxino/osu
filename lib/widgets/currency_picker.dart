import 'package:flutter/material.dart';

import '../data/currencies.dart';
import '../models/currency_info.dart';
import '../theme/app_theme.dart';

Future<CurrencyInfo?> showCurrencyPicker({
  required BuildContext context,
  required String currentCode,
  required String excludedCode,
}) {
  return showModalBottomSheet<CurrencyInfo>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.ink.withValues(alpha: 0.62),
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.88,
      child: CurrencyPickerSheet(
        currentCode: currentCode,
        excludedCode: excludedCode,
      ),
    ),
  );
}

class CurrencyPickerSheet extends StatefulWidget {
  const CurrencyPickerSheet({
    required this.currentCode,
    required this.excludedCode,
    super.key,
  });

  final String currentCode;
  final String excludedCode;

  @override
  State<CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<CurrencyPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = currencies.where((currency) {
      if (currency.code == widget.excludedCode) return false;
      return normalizedQuery.isEmpty ||
          currency.code.toLowerCase().contains(normalizedQuery) ||
          currency.name.toLowerCase().contains(normalizedQuery);
    }).toList();

    return Center(
      child: Container(
        width: 580,
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.onSurface, width: 1.5),
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(color: AppColors.ink, offset: Offset(7, 8)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CHOOSE A CURRENCY',
                          style: TextStyle(
                            color: AppColors.coralDark,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Where to next?',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontSize: 38,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                key: const Key('currency_search'),
                controller: _searchController,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search by name or code',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: colors.surfaceContainerHighest.withValues(
                    alpha: 0.45,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(color: colors.outline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(
                      color: colors.outline.withValues(alpha: 0.45),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(color: colors.onSurface, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No currency found.'))
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: colors.outline.withValues(alpha: 0.22),
                        ),
                        itemBuilder: (context, index) {
                          final currency = filtered[index];
                          final selected = currency.code == widget.currentCode;
                          return ListTile(
                            key: Key('currency_${currency.code}'),
                            onTap: () => Navigator.pop(context, currency),
                            selected: selected,
                            selectedTileColor: AppColors.lime.withValues(
                              alpha: 0.32,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            leading: Text(
                              currency.flag,
                              style: const TextStyle(fontSize: 25),
                            ),
                            title: Text(
                              currency.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              currency.symbol,
                              style: const TextStyle(fontSize: 10),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: colors.outline.withValues(alpha: 0.45),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                currency.code,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.7,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
