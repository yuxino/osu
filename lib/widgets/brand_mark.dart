import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = compact ? 38.0 : 50.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border.all(color: colors.onSurface),
            borderRadius: BorderRadius.circular(compact ? 12 : 16),
            boxShadow: const [
              BoxShadow(color: AppColors.ink, offset: Offset(3, 3)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset('assets/branding/osu_mark.png', fit: BoxFit.cover),
        ),
        const SizedBox(width: 13),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'osu',
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontSize: compact ? 24 : 30,
                height: 0.9,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.4,
              ),
            ),
            if (!compact) ...[
              const SizedBox(height: 6),
              Text(
                'CURRENCY, MADE SIMPLE',
                style: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.58),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.35,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
