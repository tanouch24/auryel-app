import 'api_client.dart';

/// Catégories de « Signaler un problème ». `wire` = valeur envoyée au backend
/// (allowlist serveur), `label` = libellé français affiché.
enum SupportCategory {
  account(wire: 'account', label: 'Problème avec mon compte'),
  consultation(wire: 'consultation', label: 'Consultation'),
  subscription(wire: 'subscription', label: 'Abonnement'),
  game(wire: 'game', label: 'Tirage / jeu'),
  meditation(wire: 'meditation', label: 'Méditation'),
  technical(wire: 'technical', label: 'Bug technique'),
  other(wire: 'other', label: 'Autre');

  const SupportCategory({required this.wire, required this.label});

  final String wire;
  final String label;
}

/// « Signaler un problème » — envoi d'un message au support Auryel.
///
///   POST /api/app/support   (Bearer)
///     { "subject": "...", "message": "...", "category": "...",
///       "app_version"?: "...", "platform"?: "..." }
///
/// Le SERVEUR est l'unique autorité sur l'identité : `user_id` et l'email du
/// compte viennent du jeton Bearer / de la base, jamais du client. Aucune
/// donnée sensible n'est jointe (ni mot de passe, ni jeton, ni contenu de
/// consultation, ni date de naissance).
///
/// Ne renvoie rien : l'appelant n'affiche la confirmation QUE si ce futur se
/// complète sans exception (2xx). Toute erreur est propagée telle quelle.
class SupportApi {
  SupportApi(this._client);

  final ApiClient _client;

  Future<void> submit({
    required String bearer,
    required String subject,
    required String message,
    required SupportCategory category,
    String? appVersion,
    String? platform,
  }) async {
    final body = <String, dynamic>{
      'subject': subject.trim(),
      'message': message.trim(),
      'category': category.wire,
      if (appVersion != null && appVersion.isNotEmpty) 'app_version': appVersion,
      if (platform != null && platform.isNotEmpty) 'platform': platform,
    };
    await _client.postJson('/api/app/support', body, bearer: bearer);
  }
}
