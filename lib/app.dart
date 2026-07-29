import 'package:flutter/material.dart';

import 'pages/converter_page.dart';
import 'services/rate_repository.dart';
import 'theme/app_theme.dart';

class OsuApp extends StatefulWidget {
  const OsuApp({
    required this.repository,
    this.initialThemeMode = ThemeMode.light,
    super.key,
  });

  final RateRepository repository;
  final ThemeMode initialThemeMode;

  @override
  State<OsuApp> createState() => _OsuAppState();
}

class _OsuAppState extends State<OsuApp> {
  late ThemeMode _themeMode = widget.initialThemeMode;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'osu — currency, made simple',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      home: ConverterPage(
        repository: widget.repository,
        isDarkMode: _themeMode == ThemeMode.dark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}
