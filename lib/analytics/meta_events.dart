import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter/foundation.dart';

/// Façade INTERNE des Meta App Events. AUCUN écran n'appelle `facebook_app_events`
/// directement — tout passe par cette interface, testable et neutralisable.
///
/// RÈGLE DE CONSENTEMENT (RGPD) : rien n'est mesuré tant que l'utilisateur n'a
/// pas donné un consentement EXPLICITE, non pré-coché et RÉVOCABLE.
///   - avant consentement / sans configuration  -> [NoopMetaEvents] :
///     aucune initialisation SDK, aucun événement, aucune collecte de
///     l'identifiant publicitaire, auto-logging désactivé ;
///   - après consentement                        -> [FacebookMetaEvents] :
///     activation SDK + les 4 événements ci-dessous, sans AUCUNE donnée
///     personnelle.
///
/// Événements autorisés (allowlist stricte) :
///   - activation / installation (géré par le SDK, sous consentement)
///   - onboarding_completed
///   - paywall_viewed
///   - subscription_started   (UNIQUEMENT après validation serveur réelle)
///   - consultation_started   (UNIQUEMENT au démarrage serveur d'une consultation)
///
/// JAMAIS transmis : email, téléphone, nom, prénom, date de naissance, message,
/// contenu de consultation, texte de tirage, conseiller choisi, user_id brut,
/// contenu Memory, journal, humeur, toute donnée sensible.
abstract class MetaEvents {
  /// `true` si la mesure Meta est active (config présente ET consentement donné).
  bool get isActive;

  /// Applique le consentement. `granted == false` -> purge des données SDK +
  /// désactivation complète (auto-log, advertiser ID). Idempotent.
  Future<void> setConsent(bool granted);

  Future<void> logOnboardingCompleted();
  Future<void> logPaywallViewed();

  /// UNIQUEMENT après `PurchaseController` succès + validation du reçu serveur.
  Future<void> logSubscriptionStarted();

  /// UNIQUEMENT quand le serveur a réellement démarré la consultation.
  Future<void> logConsultationStarted();

  /// Fabrique : implémentation réelle si [MetaConfig] complète, sinon
  /// [NoopMetaEvents]. Applique le consentement initial.
  static Future<MetaEvents> create({
    required MetaConfig config,
    required bool consentGranted,
  }) async {
    if (!config.isComplete) return const NoopMetaEvents();
    final impl = FacebookMetaEvents();
    await impl.setConsent(consentGranted);
    return impl;
  }
}

/// Configuration SDK (NON secrète — le Client Token est une config SDK mobile,
/// pas une autorité serveur ; la clé secrète Meta n'est JAMAIS utilisée ici).
/// Injectée au build :
///   --dart-define=AURYEL_META_APP_ID=...
///   --dart-define=AURYEL_META_CLIENT_TOKEN=...
class MetaConfig {
  const MetaConfig({required this.appId, required this.clientToken});

  final String appId;
  final String clientToken;

  bool get isComplete => appId.trim().isNotEmpty && clientToken.trim().isNotEmpty;

  static const MetaConfig fromEnvironment = MetaConfig(
    appId: String.fromEnvironment('AURYEL_META_APP_ID'),
    clientToken: String.fromEnvironment('AURYEL_META_CLIENT_TOKEN'),
  );
}

/// Inerte : aucune mesure, aucune collecte. Sans config, avant consentement, et
/// dans tous les tests hérités.
class NoopMetaEvents implements MetaEvents {
  const NoopMetaEvents();

  @override
  bool get isActive => false;

  @override
  Future<void> setConsent(bool granted) async {}

  @override
  Future<void> logOnboardingCompleted() async {}

  @override
  Future<void> logPaywallViewed() async {}

  @override
  Future<void> logSubscriptionStarted() async {}

  @override
  Future<void> logConsultationStarted() async {}
}

/// Implémentation réelle — enveloppe `facebook_app_events`.
class FacebookMetaEvents implements MetaEvents {
  FacebookMetaEvents({FacebookAppEvents? plugin})
      : _fb = plugin ?? FacebookAppEvents();

  final FacebookAppEvents _fb;
  bool _consent = false;

  @override
  bool get isActive => _consent;

  @override
  Future<void> setConsent(bool granted) async {
    _consent = granted;
    try {
      // Suivi publicitaire + auto-logging : activés SEULEMENT sous consentement.
      // `collectId: false` -> on NE collecte PAS l'identifiant publicitaire
      // GAID (cohérent avec AdvertiserIDCollectionEnabled=false du manifeste).
      // GAID off = déclaration Data Safety plus simple ; une activation future
      // = décision produit + ré-audit dédiés.
      await _fb.setAdvertiserTracking(enabled: granted, collectId: false);
      await _fb.setAutoLogAppEventsEnabled(granted);
      if (granted) {
        // Options de traitement standard (aucune restriction LDU) ; l'activation
        // / installation est journalisée automatiquement par le SDK une fois
        // l'auto-logging activé.
        await _fb.setDataProcessingOptions(const <String>[]);
        await _fb.flush();
      } else {
        await _fb.clearUserData();
        await _fb.flush();
      }
    } catch (e) {
      // Plugin absent (test) / erreur SDK : la mesure reste inactive.
      if (kDebugMode) debugPrint('MetaEvents setConsent KO: $e');
    }
  }

  Future<void> _log(String name) async {
    if (!isActive) return;
    try {
      await _fb.logEvent(name: name);
    } catch (e) {
      if (kDebugMode) debugPrint('MetaEvents $name KO: $e');
    }
  }

  @override
  Future<void> logOnboardingCompleted() => _log('onboarding_completed');

  @override
  Future<void> logPaywallViewed() => _log('paywall_viewed');

  @override
  Future<void> logSubscriptionStarted() => _log('subscription_started');

  @override
  Future<void> logConsultationStarted() => _log('consultation_started');
}
