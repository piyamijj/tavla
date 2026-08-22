import 'package:flutter/material.dart';

/// Cyber/neon color palette shared across the whole app: backgrounds,
/// neon accents, glow colors and the two player colors. Centralizing these
/// keeps the theme, board, dice and piece painters visually consistent.
class AppColors {
  const AppColors._();

  // Base backgrounds (deep space / dark cyber tones).
  static const Color background = Color(0xFF05050A);
  static const Color surface = Color(0xFF0B0E17);
  static const Color surfaceVariant = Color(0xFF11162A);
  static const Color panel = Color(0xFF161B2E);

  // Primary neon accents.
  static const Color neonCyan = Color(0xFF00F0FF);
  static const Color neonMagenta = Color(0xFFFF2BD6);
  static const Color neonPurple = Color(0xFF9D4BFF);
  static const Color neonGreen = Color(0xFF39FF88);
  static const Color neonYellow = Color(0xFFFFE94D);
  static const Color neonRed = Color(0xFFFF3B5C);

  // Player colors: white player rendered in neon cyan, black player in
  // neon magenta.
  static const Color playerWhite = neonCyan;
  static const Color playerBlack = neonMagenta;

  // Board tones.
  static const Color boardBase = Color(0xFF0D1022);
  static const Color pointLight = Color(0xFF1A2140);
  static const Color pointDark = Color(0xFF141830);
  static const Color barZone = Color(0xFF090B16);
  static const Color boardBorder = neonPurple;

  // Text.
  static const Color textPrimary = Color(0xFFEAF6FF);
  static const Color textSecondary = Color(0xFF8FA3C7);
  static const Color textMuted = Color(0xFF54608A);

  // Glow shadow helpers.
  static List<BoxShadow> glow(Color color, {double blur = 18, double spread = 1}) {
    return [
      BoxShadow(color: color.withOpacity(0.85), blurRadius: blur, spreadRadius: spread),
      BoxShadow(color: color.withOpacity(0.35), blurRadius: blur * 2.2, spreadRadius: spread),
    ];
  }

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF05050A), Color(0xFF0B0E1E), Color(0xFF120B22)],
  );

  static const LinearGradient cyanMagentaGradient = LinearGradient(
    colors: [neonCyan, neonMagenta],
  );
}