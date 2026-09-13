import 'package:flutter/material.dart';

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

/// Typographie Auryel — **Inter**, une seule famille pour toute l'application
/// (titres, corps, UI, navigation, dialogues).
///
/// Les fichiers de police sont EMBARQUÉS dans l'app (`fonts/Inter/*.ttf`,
/// déclarés dans `pubspec.yaml`) sous licence SIL Open Font License 1.1 —
/// aucun chargement réseau au runtime, aucune dépendance à `google_fonts`.
///
/// Graisses disponibles : 400 (Regular) · 500 (Medium) · 600 (SemiBold) ·
/// 700 (Bold). Toute autre valeur est arrondie par le moteur à la plus proche.
class AuryelText {
  AuryelText._();

  /// Nom de famille EXACT déclaré dans `pubspec.yaml`.
  static const String fontFamily = 'Inter';

  /// Repli système si la police embarquée venait à manquer (ne devrait jamais
  /// arriver — elle est dans le bundle) : jamais un serif, jamais du réseau.
  static const List<String> fontFamilyFallback = <String>[
    'Roboto', // Android
    'SF Pro Text', // iOS
    'Segoe UI', // desktop
    'sans-serif',
  ];

  static TextStyle _inter({
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    FontStyle fontStyle = FontStyle.normal,
    double? letterSpacing,
    double? height,
    // CORRECTIF UX FINAL — garantie EXPLICITE, au niveau du style partagé :
    // aucun texte Auryel n'est souligné par défaut (le rendu était déjà
    // identique avec `decoration` implicitement `null`, mais l'expliciter ici
    // élimine toute ambiguïté et toute régression future, app entière).
    TextDecoration decoration = TextDecoration.none,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      decoration: decoration,
    );
  }

  // ---------------------------------------------------------------------------
  // API historique — conservée pour ne pas toucher tous les call sites.
  // `display` ET `body` rendent désormais la MÊME famille (Inter) : la seule
  // différence est le défaut de taille/graisse.
  // ---------------------------------------------------------------------------

  /// Titres / éléments d'affichage. (Anciennement un serif — désormais Inter.)
  static TextStyle display({
    double fontSize = 28,
    FontWeight fontWeight = FontWeight.w600,
    FontStyle fontStyle = FontStyle.normal,
    Color color = AuryelColors.textCream,
    double? letterSpacing,
    double? height,
  }) {
    return _inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Corps de texte / UI.
  static TextStyle body({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = AuryelColors.textSecondary,
    double? letterSpacing,
    double? height,
  }) {
    return _inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  // ---------------------------------------------------------------------------
  // Échelle SÉMANTIQUE Auryel — à privilégier pour tout nouveau code. Une seule
  // hiérarchie, cohérente d'un écran à l'autre. (cf. UX-B §3)
  // ---------------------------------------------------------------------------

  /// Grand titre d'écran — 28 / 700.
  static TextStyle screenTitle({Color color = AuryelColors.textCream}) =>
      _inter(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: color,
        height: 1.15,
      );

  /// Titre de section — 21 / 600.
  static TextStyle sectionTitle({Color color = AuryelColors.textCream}) =>
      _inter(
        fontSize: 21,
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.2,
      );

  /// Titre de carte / bloc — 17 / 600.
  static TextStyle cardTitle({Color color = AuryelColors.textCream}) => _inter(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: color,
    height: 1.25,
  );

  /// Texte principal — 15.5 / 400.
  static TextStyle bodyText({Color color = AuryelColors.textSecondary}) =>
      _inter(
        fontSize: 15.5,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.5,
      );

  /// Texte secondaire — 13.5 / 400.
  static TextStyle bodySecondary({Color color = AuryelColors.textMuted}) =>
      _inter(
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.45,
      );

  /// Libellé de bouton — 15.5 / 600.
  static TextStyle button({Color color = AuryelColors.backgroundDeep}) =>
      _inter(
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.2,
      );

  /// Libellé de navigation basse — 11.5 / 600.
  static TextStyle navLabel({required Color color, bool active = false}) =>
      _inter(
        fontSize: 11.5,
        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
        color: color,
        letterSpacing: 0.2,
      );

  /// Sur-titre / étiquette capitale (« PRÉSENTATION VOCALE ») — 11 / 600 espacé.
  static TextStyle overline({Color color = AuryelColors.textMuted}) => _inter(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: color,
    letterSpacing: 1.4,
  );
}

class AuryelTheme {
  AuryelTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = base.textTheme.apply(
      fontFamily: AuryelText.fontFamily,
      fontFamilyFallback: AuryelText.fontFamilyFallback,
      bodyColor: AuryelColors.textSecondary,
      displayColor: AuryelColors.textCream,
    );
    return base.copyWith(
      scaffoldBackgroundColor: AuryelColors.backgroundDeep,
      // Famille par défaut de TOUT texte qui n'a pas de style explicite
      // (dialogues Material, snackbars, tooltips…) : Inter, embarquée.
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      colorScheme: base.colorScheme.copyWith(
        surface: AuryelColors.surface,
        primary: AuryelColors.gold,
        secondary: AuryelColors.goldLight,
        onSurface: AuryelColors.textCream,
      ),
      dividerColor: AuryelColors.warmBorder,
      splashColor: AuryelColors.gold.withValues(alpha: 0.08),
      highlightColor: Colors.transparent,
    );
  }
}
