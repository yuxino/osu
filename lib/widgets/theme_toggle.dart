import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ThemeToggle extends StatelessWidget {
  const ThemeToggle({required this.isDark, required this.onTap, super.key});

  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Switch to ${isDark ? 'light' : 'dark'} theme',
      child: InkWell(
        key: const Key('theme_toggle'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          width: 60,
          height: 34,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            border: Border.all(color: colors.onSurface, width: 1.3),
            borderRadius: BorderRadius.circular(99),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: AppColors.lime,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: AppColors.ink, offset: Offset(1.5, 1.5)),
                ],
              ),
              child: Icon(
                isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                size: 14,
                color: AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
