import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/currencies.dart';
import '../models/currency_info.dart';
import '../models/rate_quote.dart';
import '../services/rate_repository.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
import '../widgets/brand_mark.dart';
import '../widgets/currency_picker.dart';
import '../widgets/money_card.dart';
import '../widgets/theme_toggle.dart';

enum _ActiveSide { from, to }

class ConverterPage extends StatefulWidget {
  const ConverterPage({
    required this.repository,
    required this.isDarkMode,
    required this.onToggleTheme,
    super.key,
  });

  final RateRepository repository;
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  @override
  State<ConverterPage> createState() => _ConverterPageState();
}

class _ConverterPageState extends State<ConverterPage> {
  final _fromController = TextEditingController(text: '1000');
  final _toController = TextEditingController();

  CurrencyInfo _fromCurrency = currencyByCode('CNY');
  CurrencyInfo _toCurrency = currencyByCode('USD');
  _ActiveSide _activeSide = _ActiveSide.from;
  RateQuote? _quote;
  String? _message;
  bool _loading = true;
  bool _syncingControllers = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadRate();
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  Future<void> _loadRate() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final result = await widget.repository.getRate(
        base: _fromCurrency.code,
        quote: _toCurrency.code,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _quote = result;
        _loading = false;
        _message = result.isCached
            ? 'Offline — using your last saved rate.'
            : null;
      });
      _recalculate();
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _message = 'Rates are taking a break. Try again in a moment.';
      });
    }
  }

  void _replaceText(TextEditingController controller, String value) {
    _syncingControllers = true;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _syncingControllers = false;
  }

  void _recalculate() {
    final rate = _quote?.rate;
    if (rate == null) return;

    if (_activeSide == _ActiveSide.from) {
      final amount = parseAmount(_fromController.text);
      _replaceText(
        _toController,
        formatAmount(amount == null ? null : amount * rate, _toCurrency.code),
      );
    } else {
      final amount = parseAmount(_toController.text);
      _replaceText(
        _fromController,
        formatAmount(amount == null ? null : amount / rate, _fromCurrency.code),
      );
    }
    if (mounted) setState(() {});
  }

  void _handleAmountChanged(_ActiveSide side, String value) {
    if (_syncingControllers) return;
    _activeSide = side;
    final sanitized = sanitizeAmountInput(value);
    final controller = side == _ActiveSide.from
        ? _fromController
        : _toController;
    if (sanitized != value) _replaceText(controller, sanitized);
    _recalculate();
  }

  Future<void> _chooseCurrency(_ActiveSide side) async {
    final current = side == _ActiveSide.from ? _fromCurrency : _toCurrency;
    final excluded = side == _ActiveSide.from ? _toCurrency : _fromCurrency;
    final selected = await showCurrencyPicker(
      context: context,
      currentCode: current.code,
      excludedCode: excluded.code,
    );
    if (selected == null || !mounted) return;

    setState(() {
      if (side == _ActiveSide.from) {
        _fromCurrency = selected;
      } else {
        _toCurrency = selected;
      }
    });
    await _loadRate();
  }

  Future<void> _swapCurrencies() async {
    final convertedAmount = _activeSide == _ActiveSide.from
        ? _toController.text
        : _fromController.text;
    setState(() {
      final previousFrom = _fromCurrency;
      _fromCurrency = _toCurrency;
      _toCurrency = previousFrom;
      _activeSide = _ActiveSide.from;
      _replaceText(
        _fromController,
        convertedAmount.isEmpty ? '0' : convertedAmount,
      );
      _replaceText(_toController, '');
    });
    await _loadRate();
  }

  Future<void> _selectQuickPair(String from, String to) async {
    setState(() {
      _fromCurrency = currencyByCode(from);
      _toCurrency = currencyByCode(to);
      _activeSide = _ActiveSide.from;
    });
    await _loadRate();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: 90,
            left: -120,
            child: _AmbientCircle(
              size: 330,
              color: AppColors.sky.withValues(alpha: 0.32),
            ),
          ),
          Positioned(
            top: 560,
            right: -90,
            child: _AmbientCircle(
              size: 280,
              color: AppColors.lime.withValues(alpha: 0.23),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    children: [
                      _Header(
                        isDarkMode: widget.isDarkMode,
                        onToggleTheme: widget.onToggleTheme,
                      ),
                      const SizedBox(height: 68),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 900;
                          final copy = _HeroCopy(compact: !isWide);
                          final converter = _ConverterCard(
                            fromCurrency: _fromCurrency,
                            toCurrency: _toCurrency,
                            fromController: _fromController,
                            toController: _toController,
                            activeSide: _activeSide,
                            quote: _quote,
                            loading: _loading,
                            message: _message,
                            onFromChanged: (value) =>
                                _handleAmountChanged(_ActiveSide.from, value),
                            onToChanged: (value) =>
                                _handleAmountChanged(_ActiveSide.to, value),
                            onFromTap: () =>
                                setState(() => _activeSide = _ActiveSide.from),
                            onToTap: () =>
                                setState(() => _activeSide = _ActiveSide.to),
                            onChooseFrom: () =>
                                _chooseCurrency(_ActiveSide.from),
                            onChooseTo: () => _chooseCurrency(_ActiveSide.to),
                            onSwap: _swapCurrencies,
                          );

                          if (isWide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(flex: 9, child: copy),
                                const SizedBox(width: 76),
                                Expanded(flex: 11, child: converter),
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              copy,
                              const SizedBox(height: 58),
                              converter,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 105),
                      _QuickPairs(
                        selectedFrom: _fromCurrency.code,
                        selectedTo: _toCurrency.code,
                        onSelect: _selectQuickPair,
                      ),
                      const SizedBox(height: 70),
                      Divider(color: colors.outline.withValues(alpha: 0.34)),
                      const SizedBox(height: 22),
                      const _Footer(),
                      const SizedBox(height: 26),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.isDarkMode, required this.onToggleTheme});

  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return Container(
          height: compact ? 88 : 104,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colors.outline.withValues(alpha: 0.32)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              BrandMark(compact: compact),
              Row(
                children: [
                  if (!compact) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: colors.outline.withValues(alpha: 0.42),
                        ),
                        borderRadius: BorderRadius.circular(99),
                        color: colors.surface.withValues(alpha: 0.65),
                      ),
                      child: const Row(
                        children: [
                          _LiveDot(),
                          SizedBox(width: 8),
                          Text(
                            'REFERENCE RATES',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                  ],
                  ThemeToggle(isDark: isDarkMode, onTap: onToggleTheme),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: Color(0xFF41A36F),
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Color(0x3341A36F), spreadRadius: 4)],
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final headingStyle = theme.textTheme.displayLarge!.copyWith(
      fontSize: compact ? 64 : 86,
      color: colors.onSurface,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TINY TOOL · BIG WORLD',
          style: TextStyle(
            color: AppColors.coralDark,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 20),
        Text('Money\nmoves.', style: headingStyle),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -5,
              right: -4,
              bottom: 5,
              height: compact ? 16 : 20,
              child: Transform.rotate(
                angle: -0.018,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.lime,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
            Text('Keep it\nsimple.', style: headingStyle),
          ],
        ),
        const SizedBox(height: 27),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 475),
          child: Text(
            'Fresh reference rates for wherever you’re going next. '
            'No noise, no signup—just the number you need.',
            style: theme.textTheme.bodyLarge,
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 32),
          Transform.rotate(
            angle: -0.05,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  color: colors.onSurface.withValues(alpha: 0.54),
                ),
                const SizedBox(width: 8),
                Text(
                  'made for borderless days',
                  style: TextStyle(
                    color: colors.onSurface.withValues(alpha: 0.56),
                    fontFamily: 'Fraunces',
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ConverterCard extends StatelessWidget {
  const _ConverterCard({
    required this.fromCurrency,
    required this.toCurrency,
    required this.fromController,
    required this.toController,
    required this.activeSide,
    required this.quote,
    required this.loading,
    required this.message,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onFromTap,
    required this.onToTap,
    required this.onChooseFrom,
    required this.onChooseTo,
    required this.onSwap,
  });

  final CurrencyInfo fromCurrency;
  final CurrencyInfo toCurrency;
  final TextEditingController fromController;
  final TextEditingController toController;
  final _ActiveSide activeSide;
  final RateQuote? quote;
  final bool loading;
  final String? message;
  final ValueChanged<String> onFromChanged;
  final ValueChanged<String> onToChanged;
  final VoidCallback onFromTap;
  final VoidCallback onToTap;
  final VoidCallback onChooseFrom;
  final VoidCallback onChooseTo;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final date = quote == null
        ? 'just a moment'
        : DateFormat('MMM d, y', 'en_US').format(quote!.date);

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, progress, child) {
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, (1 - progress) * 22),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 13, bottom: 14),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              left: 14,
              top: 13,
              right: -12,
              bottom: -12,
              child: Transform.rotate(
                angle: 0.025,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.sky,
                    border: Border.all(color: AppColors.ink, width: 1.4),
                    borderRadius: BorderRadius.circular(34),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(37, 31, 37, 32),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border.all(color: colors.onSurface, width: 1.5),
                borderRadius: BorderRadius.circular(32),
                boxShadow: const [
                  BoxShadow(color: AppColors.ink, offset: Offset(8, 9)),
                ],
              ),
              child: ClipRect(
                child: Stack(
                  children: [
                    Positioned(
                      top: -76,
                      right: -76,
                      child: Container(
                        width: 145,
                        height: 115,
                        decoration: BoxDecoration(
                          color: AppColors.lime,
                          border: Border.all(color: AppColors.ink, width: 1.5),
                          borderRadius: BorderRadius.circular(60),
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'TODAY’S EXCHANGE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 17),
                              child: _RateDot(
                                loading: loading,
                                hasError: quote == null && message != null,
                                cached: quote?.isCached ?? false,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 25),
                        MoneyCard(
                          fieldKey: const Key('from_amount'),
                          currencyButtonKey: const Key('from_currency_button'),
                          label: 'You send',
                          currency: fromCurrency,
                          controller: fromController,
                          isActive: activeSide == _ActiveSide.from,
                          loading: loading,
                          onChanged: onFromChanged,
                          onTap: onFromTap,
                          onChooseCurrency: onChooseFrom,
                        ),
                        SizedBox(
                          height: 57,
                          child: Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: colors.outline.withValues(alpha: 0.35),
                                ),
                              ),
                              const SizedBox(width: 13),
                              _SwapButton(onPressed: onSwap),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Divider(
                                  color: colors.outline.withValues(alpha: 0.35),
                                ),
                              ),
                            ],
                          ),
                        ),
                        MoneyCard(
                          fieldKey: const Key('to_amount'),
                          currencyButtonKey: const Key('to_currency_button'),
                          label: 'You get',
                          currency: toCurrency,
                          controller: toController,
                          isActive: activeSide == _ActiveSide.to,
                          loading: loading,
                          onChanged: onToChanged,
                          onTap: onToTap,
                          onChooseCurrency: onChooseTo,
                        ),
                        const SizedBox(height: 25),
                        Container(
                          padding: const EdgeInsets.only(top: 18),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: colors.outline.withValues(alpha: 0.38),
                                style: BorderStyle.solid,
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'MID-MARKET REFERENCE',
                                      style: TextStyle(
                                        color: colors.onSurface.withValues(
                                          alpha: 0.54,
                                        ),
                                        fontSize: 8,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.15,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      quote == null
                                          ? 'Fetching a fresh rate…'
                                          : '1 ${fromCurrency.code} = '
                                                '${formatRate(quote!.rate)} '
                                                '${toCurrency.code}',
                                      key: const Key('rate_label'),
                                      style: const TextStyle(
                                        fontFamily: 'Fraunces',
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                date,
                                style: TextStyle(
                                  color: colors.onSurface.withValues(
                                    alpha: 0.55,
                                  ),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (message != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.coral.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Text(
                              message!,
                              key: const Key('rate_message'),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RateDot extends StatelessWidget {
  const _RateDot({
    required this.loading,
    required this.hasError,
    required this.cached,
  });

  final bool loading;
  final bool hasError;
  final bool cached;

  @override
  Widget build(BuildContext context) {
    final color = hasError
        ? AppColors.coralDark
        : cached
        ? const Color(0xFFD5993D)
        : loading
        ? AppColors.coral
        : const Color(0xFF41A36F);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.2), spreadRadius: 5),
        ],
      ),
    );
  }
}

class _SwapButton extends StatelessWidget {
  const _SwapButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        boxShadow: [BoxShadow(color: AppColors.ink, offset: Offset(3, 3))],
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: IconButton(
        key: const Key('swap_button'),
        onPressed: onPressed,
        tooltip: 'Swap currencies',
        style: IconButton.styleFrom(
          fixedSize: const Size(43, 43),
          backgroundColor: AppColors.coral,
          foregroundColor: AppColors.warmWhite,
          side: const BorderSide(color: AppColors.ink, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(Icons.swap_vert_rounded),
      ),
    );
  }
}

class _QuickPairs extends StatelessWidget {
  const _QuickPairs({
    required this.selectedFrom,
    required this.selectedTo,
    required this.onSelect,
  });

  final String selectedFrom;
  final String selectedTo;
  final Future<void> Function(String from, String to) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 780;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'WELL-TRAVELLED PAIRS',
              style: TextStyle(
                color: AppColors.coralDark,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.7,
              ),
            ),
            const SizedBox(height: 10),
            Text('Take a shortcut.', style: theme.textTheme.displayMedium),
          ],
        );

        final pairs = Wrap(
          spacing: 12,
          runSpacing: 12,
          children: quickPairs.map((pair) {
            final from = currencyByCode(pair.$1);
            final to = currencyByCode(pair.$2);
            final selected = from.code == selectedFrom && to.code == selectedTo;
            return _QuickPairButton(
              from: from,
              to: to,
              selected: selected,
              width: wide ? 250 : constraints.maxWidth,
              onTap: () => onSelect(from.code, to.code),
            );
          }).toList(),
        );

        return Container(
          padding: const EdgeInsets.only(top: 40),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colors.outline.withValues(alpha: 0.34)),
            ),
          ),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(flex: 4, child: heading),
                    const SizedBox(width: 60),
                    Expanded(flex: 6, child: pairs),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heading, const SizedBox(height: 27), pairs],
                ),
        );
      },
    );
  }
}

class _QuickPairButton extends StatelessWidget {
  const _QuickPairButton({
    required this.from,
    required this.to,
    required this.selected,
    required this.width,
    required this.onTap,
  });

  final CurrencyInfo from;
  final CurrencyInfo to;
  final bool selected;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      key: Key('quick_${from.code}_${to.code}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: width,
        height: 55,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: selected ? AppColors.lime : colors.surface,
          border: Border.all(
            color: selected ? AppColors.ink : colors.outline,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: selected
              ? const [BoxShadow(color: AppColors.ink, offset: Offset(3, 3))]
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${from.flag}  ${from.code}',
                style: TextStyle(
                  color: selected ? AppColors.ink : colors.onSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: AppColors.coralDark,
            ),
            Expanded(
              child: Text(
                '${to.flag}  ${to.code}',
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: selected ? AppColors.ink : colors.onSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;
        final disclaimer = Text(
          'Rates by Frankfurter. For reference only, not a trading quote.',
          style: TextStyle(
            color: colors.onSurface.withValues(alpha: 0.55),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const BrandMark(compact: true),
                  Text(
                    '© ${DateTime.now().year}',
                    style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.55),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              disclaimer,
            ],
          );
        }

        return Row(
          children: [
            const BrandMark(compact: true),
            const Spacer(),
            disclaimer,
            const SizedBox(width: 38),
            Text(
              '© ${DateTime.now().year}',
              style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.55),
                fontSize: 10,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AmbientCircle extends StatelessWidget {
  const _AmbientCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Transform.rotate(
        angle: math.pi / 12,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
