import 'package:flutter/material.dart';

class AppThemePreset {
  const AppThemePreset({
    required this.id,
    required this.name,
    required this.lightSeed,
    required this.darkSeed,
  });

  final String id;
  final String name;
  final Color lightSeed;
  final Color darkSeed;

  Color seedFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkSeed : lightSeed;

  static const blue = AppThemePreset(
    id: 'blue',
    name: 'Azul',
    lightSeed: Color(0xFF5B6CFF),
    darkSeed: Color(0xFF8FA0FF),
  );
  static const purple = AppThemePreset(
    id: 'purple',
    name: 'Neón morado',
    lightSeed: Color(0xFF8F5BFF),
    darkSeed: Color(0xFFB47CFF),
  );
  static const teal = AppThemePreset(
    id: 'teal',
    name: 'Verde azulado',
    lightSeed: Color(0xFF00A6A6),
    darkSeed: Color(0xFF5DE2D6),
  );
  static const amber = AppThemePreset(
    id: 'amber',
    name: 'Ámbar',
    lightSeed: Color(0xFFFFA726),
    darkSeed: Color(0xFFFFD180),
  );
  static const rose = AppThemePreset(
    id: 'rose',
    name: 'Rosa',
    lightSeed: Color(0xFFEC407A),
    darkSeed: Color(0xFFFF9EB8),
  );

  static const values = [blue, purple, teal, amber, rose];

  static ThemeData buildTheme(AppThemePreset preset, Brightness brightness) {
    final seed = preset.seedFor(brightness);
    final base = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

    final surface = brightness == Brightness.dark
        ? const Color(0xFF101114)
        : const Color(0xFFF3F3F7);
    final surfaceContainer = brightness == Brightness.dark
        ? const Color(0xFF171A22)
        : const Color(0xFFE8EAF3);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: base.copyWith(
        surface: surface,
        surfaceContainerHighest: surfaceContainer,
        onSurface: brightness == Brightness.dark ? Colors.white : Colors.black,
      ),
      scaffoldBackgroundColor: surface,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: brightness == Brightness.dark
            ? Colors.white
            : Colors.black,
      ),
      cardColor: surfaceContainer,
      popupMenuTheme: PopupMenuThemeData(color: surfaceContainer),
    );
  }
}
