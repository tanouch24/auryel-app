import 'api_client.dart';

/// Raison d'un signalement de réponse IA. `wire` = valeur envoyée au backend,
/// `label` = libellé français affiché dans la feuille de signalement.
enum AiReportReason {
  inappropriate(wire: 'inappropriate', label: 'Réponse inappropriée'),
  unsafe(wire: 'unsafe', label: 'Réponse dangereuse'),
  misleading(wire: 'misleading', label: 'Réponse trompeuse'),
  other(wire: 'other', label: 'Autre');

  const AiReportReason({required this.wire, required this.label});

  final String wire;
  final String label;
}

/// Signalement d'une réponse IA / conseiller (exigence Google Play : mécanique
/// de signalement du contenu généré). Réutilise l'[ApiClient] commun — aucun
/// second client HTTP.
///
///   POST /api/app/ai/report   (Bearer)
///     { "message_id"?: "...", "consultation_id"?: "...",
///       "reason": "unsafe", "comment"?: "..." }
///
/// Le backend expose désormais un `message_id` stable : porté par
/// [ConsultationMessageDto.messageId] (historique) et
/// [ConsultationMessageResponse.replyMessageId] (réponse d'envoi). Il est
/// passé ici quand il existe ; sinon (réponse d'un backend ancien) il est
/// `null` et [report] l'omet — `consultation_id` sert alors de contexte.
/// Jamais de `message_id` fabriqué.
class AiReportApi {
  AiReportApi(this._client);

  final ApiClient _client;

  /// Envoie le signalement. Ne renvoie rien : l'appelant n'affiche la
  /// confirmation QUE si ce futur se complète sans exception (2xx serveur).
  /// Toute erreur ([ApiException], [ApiNetworkException], [ApiUnauthorizedException])
  /// est propagée telle quelle.
  Future<void> report({
    required String bearer,
    required AiReportReason reason,
    String? messageId,
    String? consultationId,
    String? comment,
  }) async {
    final trimmedComment = comment?.trim();
    await _client.postJson('/api/app/ai/report', {
      'reason': reason.wire,
      if (messageId != null && messageId.isNotEmpty) 'message_id': messageId,
      if (consultationId != null && consultationId.isNotEmpty)
        'consultation_id': consultationId,
      if (trimmedComment != null && trimmedComment.isNotEmpty)
        'comment': trimmedComment,
    }, bearer: bearer);
  }
}
