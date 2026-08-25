import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tokens de design Auryel — couleurs, dégradés, typographies.
/// Tout écran doit consommer ces tokens plutôt que des valeurs en dur.
class AuryelColors {
  AuryelColors._();

  // Fond
  static const Color backgroundDeep = Color(0xFF120E17);
  static const Color backgroundMid = Color(0xFF171120);
  static const Color backgroundLow = Color(0xFF100C16);

  // Surfaces
  static const Color surface = Color(0xFF1C1626);
  static const Color surfaceLight = Color(0xFF241C30);

  // Or
  static const Color gold = Color(0xFFC6A24E);
  static const Color goldLight = Color(0xFFE4CE88);
  static const Color goldDark = Color(0xFFA9863A);

  // Texte
  static const Color textCream = Color(0xFFF0E9DA);
  static const Color textSecondary = Color(0xFFECE4D4);
  static const Color textMuted = Color(0xFF9A8FA6);

  // Liseré
  static const Color warmBorder = Color(0xFF3A2E20);

  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE7D08A), Color(0xFFC6A24E), Color(0xFFA9863A)],
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundDeep, backgroundMid, backgroundLow],
  );
}

/// Typographies Auryel : Cormorant Garamond pour le display littéraire,
/// Inter pour le corps / l'UI.
class AuryelText {
  AuryelText._();

  static TextStyle display({
    double fontSize = 32,
    FontWeight fontWeight = FontWeight.w500,
    FontStyle fontStyle = FontStyle.normal,
    Color color = AuryelColors.textCream,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.cormorantGaramond(
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle body({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = AuryelColors.textSecondary,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}

class AuryelTheme {
  AuryelTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AuryelColors.backgroundDeep,
      colorScheme: base.colorScheme.copyWith(
        surface: AuryelColors.surface,
        primary: AuryelColors.gold,
        secondary: AuryelColors.goldLight,
        onSurface: AuryelColors.textCream,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: AuryelColors.textSecondary,
        displayColor: AuryelColors.textCream,
      ),
      dividerColor: AuryelColors.warmBorder,
      splashColor: AuryelColors.gold.withValues(alpha: 0.08),
      highlightColor: Colors.transparent,
    );
  }
}
