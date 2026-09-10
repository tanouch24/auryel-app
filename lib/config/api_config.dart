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
///  - EN DEBUG : `AURYEL_API_BASE_URL` s'il est fourni (non vide), sinon repli
///    `http://10.0.2.2:8000` (`10.0.2.2` = le `localhost` de l'hôte vu depuis
///    l'émulateur Android). Aucun contrôle strict : `localhost`, `10.0.2.2`,
///    HTTP en clair sont autorisés pour le développement.
///  - EN RELEASE / PROFILE — GARDE-FOU AUR-C02 : `AURYEL_API_BASE_URL` est
///    OBLIGATOIRE et doit être une URL **HTTPS publique**. Toute valeur
///    absente, non-HTTPS, `localhost` / `127.0.0.1` / `10.0.2.2` / IP privée /
///    hôte non qualifié -> [StateError] IMMÉDIAT au premier accès (= au
///    démarrage de l'app). Jamais de repli, jamais une release qui tape
///    silencieusement une URL de dev.
///    (Le build Gradle refuse DÉJÀ, en amont, un `assembleRelease` /
///    `bundleRelease` avec une telle URL — cf. android/app/build.gradle.kts.
///    Ce contrôle Dart est la seconde barrière.)
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

    if (!isReleaseLike) {
      // DEBUG : permissif. Override si fourni (non vide), sinon repli local.
      if (hasOverride && trimmed.isNotEmpty) return _stripTrailingSlash(trimmed);
      return debugFallbackBaseUrl;
    }

    // RELEASE / PROFILE : garde-fou strict.
    if (!hasOverride || trimmed.isEmpty) {
      throw StateError(
        'AURYEL_API_BASE_URL absent : une build release/profile DOIT fournir '
        '--dart-define=AURYEL_API_BASE_URL=https://<backend de production> '
        '(aucun repli en prod).',
      );
    }
    final reason = releaseUrlRejectionReason(trimmed);
    if (reason != null) {
      throw StateError(
        'AURYEL_API_BASE_URL invalide pour une build release : $reason. '
        'Valeur reçue : "$trimmed". Fournir une URL HTTPS publique du backend '
        'de production.',
      );
    }
    return _stripTrailingSlash(trimmed);
  }

  /// Raison pour laquelle `raw` est refusé comme base URL d'une build RELEASE,
  /// ou `null` si l'URL est acceptable. Pur / testable.
  ///
  /// Refus : URL non absolue, schéma != https (HTTP en clair interdit en
  /// release), hôte local / émulateur / IP privée / loopback, `*.local`,
  /// `host.docker.internal`, ou nom d'hôte sans point (non qualifié).
  static String? releaseUrlRejectionReason(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'URL absolue attendue (schéma + hôte)';
    }
    if (uri.scheme.toLowerCase() != 'https') {
      return 'schéma "${uri.scheme}" refusé — HTTPS obligatoire';
    }
    final host = uri.host.toLowerCase();
    const localHosts = <String>{
      'localhost',
      '127.0.0.1',
      '::1',
      '0.0.0.0',
      '10.0.2.2', // émulateur Android -> hôte
      '10.0.3.2', // Genymotion -> hôte
      'host.docker.internal',
    };
    if (localHosts.contains(host)) {
      return 'hôte local/émulateur "$host" interdit';
    }
    if (host.endsWith('.local')) {
      return 'hôte de développement "$host" interdit';
    }
    if (_isPrivateOrLoopbackIpv4(host)) {
      return 'adresse IP privée/loopback "$host" interdite';
    }
    if (!host.contains('.')) {
      return 'nom d\'hôte non qualifié "$host" — domaine public attendu';
    }
    return null;
  }

  /// `true` si `host` est une IPv4 loopback (127.x) ou privée
  /// (10.x, 192.168.x, 172.16–31.x, 169.254.x, 0.x).
  static bool _isPrivateOrLoopbackIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
      octets.add(n);
    }
    final a = octets[0], b = octets[1];
    if (a == 10 || a == 127 || a == 0) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 169 && b == 254) return true;
    return false;
  }

  static String _stripTrailingSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  /// `true` si la base pointe vers du HTTP en clair (dev local uniquement).
  static bool get isCleartext => baseUrl.startsWith('http://');
}
