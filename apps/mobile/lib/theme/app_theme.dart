import 'package:flutter/material.dart';

ThemeData buildPulseMeshTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF68E0CF),
    brightness: Brightness.dark,
    surface: const Color(0xFF0B171C),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF071015),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF0B171C),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF24404A)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF24404A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF68E0CF)),
      ),
    ),
  );
}
