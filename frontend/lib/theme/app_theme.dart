import 'package:flutter/material.dart';

class AppTheme {
  static const Color backgroundColor = Color(0xFF0A0E1A);
  static const Color surfaceColor = Color(0xFF111827);
  static const Color cardColor = Color(0xFF1C2333);
  static const Color borderColor = Color(0xFF2D3748);

  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);

  static const Color onlineColor = Color(0xFF22C55E);
  static const Color offlineColor = Color(0xFFEF4444);

  static const Color accentGreen = Color(0xFF22C55E);
  static const Color accentCyan = Color(0xFF06B6D4);
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color accentPurple = Color(0xFFA78BFA);

  static Color tpsColor(double tps) {
    if (tps >= 18) return accentGreen;
    if (tps >= 15) return accentAmber;
    return offlineColor;
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: const ColorScheme.dark(
        primary: accentCyan,
        secondary: accentGreen,
        surface: surfaceColor,
        error: offlineColor,
      ),
      fontFamily: 'monospace',
      useMaterial3: true,
    );
  }
}
