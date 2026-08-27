import 'package:flutter/foundation.dart';

/// Configuration réseau — la base URL du backend Auryel.
///
/// Fournie au build via `--dart-define` :
///   flutter run   --dart-define=AURYEL_API_BASE_URL=http://10.0.2.2:8000
///   flutter build --dart-define=AURYEL_API_BASE_URL=https://api.auryel.example
///
/// Rien de secret ici : c'est une adresse d'API, pas une clé.
///
/// Résolution :
///  - `AURYEL_API_BASE_URL` fourni (non vide)  -> utilisé.
///  - absent EN DEBUG                          -> repli `http://10.0.2.2:8000`
///    (`10.0.2.2` = le `localhost` de l'hôte vu depuis l'émulateur Android ;
///     port 8000 car 5000 est pris par « AirPlay Receiver » sur macOS).
///  - absent EN RELEASE / PROFILE              -> [StateError] explicite
///    (fail fast : jamais de build de prod qui tape silencieusement 10.0.2.2).
class ApiConfig {
  ApiConfig._();

  static const bool _hasOverride = bool.hasEnvironment('AURYEL_API_BASE_URL');
  static const String _override = String.fromEnvironment('AURYEL_API_BASE_URL');

  static const String debugFallbackBaseUrl = 'http://10.0.2.2:8000';

  static String get baseUrl => resolveBaseUrl(
        hasOverride: _hasOverride,
        override: _override,
        isReleaseLike: kReleaseMode || kProfileMode,
      );

  /// Logique pure et testable, indépendante des constantes de build.
  static String resolveBaseUrl({
    required bool hasOverride,
    required String override,
    required bool isReleaseLike,
  }) {
    final trimmed = override.trim();
    if (hasOverride && trimmed.isNotEmpty) {
      return _stripTrailingSlash(trimmed);
    }
    if (isReleaseLike) {
      throw StateError(
        'AURYEL_API_BASE_URL absent : une build release/profile doit fournir '
        '--dart-define=AURYEL_API_BASE_URL=https://… (aucun repli en prod).',
      );
    }
    return debugFallbackBaseUrl;
  }

  static String _stripTrailingSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  /// `true` si la base pointe vers du HTTP en clair (dev local uniquement).
  static bool get isCleartext => baseUrl.startsWith('http://');
}
