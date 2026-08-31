/// DTO d'une consultation 2 h renvoyée par `POST /api/consultation/message`.
class ConsultationDto {
  const ConsultationDto({
    required this.id,
    required this.advisorId,
    required this.startedAt,
    required this.expiresAt,
    required this.secondsRemaining,
    required this.creditSource,
    required this.openedNow,
  });

  final String id;

  /// Clé conseiller backend (`selena`…`raphael`) — SOURCE DE VÉRITÉ du header
  /// pendant la session, prime sur le conseiller du profil.
  final String advisorId;
  final DateTime? startedAt;
  final DateTime? expiresAt;

  /// Secondes restantes telles qu'envoyées par le serveur (F3 ne fait pas de
  /// décompte local seconde par seconde — c'est F4).
  final int secondsRemaining;
  final String creditSource;
  final bool openedNow;

  factory ConsultationDto.fromJson(Map<String, dynamic> json) =>
      ConsultationDto(
        id: (json['id'] ?? '').toString(),
        advisorId: (json['advisor_id'] ?? '').toString(),
        startedAt: _date(json['started_at']),
        expiresAt: _date(json['expires_at']),
        secondsRemaining: _int(json['seconds_remaining']),
        creditSource: (json['credit_source'] ?? '').toString(),
        openedNow: json['opened_now'] == true,
      );
}

/// DTO du quota de consultations.
class QuotaDto {
  const QuotaDto({
    required this.isPremium,
    required this.monthlyLimit,
    required this.monthlyUsed,
    required this.monthlyRemaining,
    required this.earnedAvailable,
    required this.periodStart,
    required this.periodEnd,
    this.firstFreeAvailable = false,
  });

  final bool isPremium;
  final int monthlyLimit;
  final int monthlyUsed;
  final int monthlyRemaining;
  final int earnedAvailable;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  /// `first_free_available` du backend : `true` tant que la 1re consultation
  /// offerte (1×/compte, à vie) n'a pas été consommée. Absent des anciennes
  /// réponses / fixtures -> `false` (comportement sûr : pas de gratuite).
  final bool firstFreeAvailable;

  factory QuotaDto.fromJson(Map<String, dynamic> json) => QuotaDto(
    isPremium: json['is_premium'] == true,
    monthlyLimit: _int(json['monthly_limit']),
    monthlyUsed: _int(json['monthly_used']),
    monthlyRemaining: _int(json['monthly_remaining']),
    earnedAvailable: _int(json['earned_available']),
    periodStart: _date(json['period_start']),
    periodEnd: _date(json['period_end']),
    firstFreeAvailable: json['first_free_available'] == true,
  );
}

/// Réponse 200 de `POST /api/consultation/message`.
class ConsultationMessageResponse {
  const ConsultationMessageResponse({
    required this.reply,
    required this.consultation,
    required this.quota,
  });

  final String reply;
  final ConsultationDto? consultation;
  final QuotaDto quota;

  factory ConsultationMessageResponse.fromJson(Map<String, dynamic> json) {
    final c = json['consultation'];
    final q = json['quota'];
    return ConsultationMessageResponse(
      reply: (json['reply'] ?? '').toString(),
      consultation: c is Map<String, dynamic>
          ? ConsultationDto.fromJson(c)
          : null,
      quota: q is Map<String, dynamic>
          ? QuotaDto.fromJson(q)
          : const QuotaDto(
              isPremium: false,
              monthlyLimit: 0,
              monthlyUsed: 0,
              monthlyRemaining: 0,
              earnedAvailable: 0,
              periodStart: null,
              periodEnd: null,
            ),
    );
  }
}

/// Réponse 200 de `GET /api/consultation/state` (F4). Lecture seule : aucun
/// crédit consommé, `consultation` vaut `null` s'il n'y a pas de session active.
class ConsultationStateResponse {
  const ConsultationStateResponse({
    required this.consultation,
    required this.quota,
  });

  final ConsultationDto? consultation;
  final QuotaDto quota;

  factory ConsultationStateResponse.fromJson(Map<String, dynamic> json) {
    final c = json['consultation'];
    final q = json['quota'];
    return ConsultationStateResponse(
      consultation: c is Map<String, dynamic>
          ? ConsultationDto.fromJson(c)
          : null,
      quota: q is Map<String, dynamic>
          ? QuotaDto.fromJson(q)
          : const QuotaDto(
              isPremium: false,
              monthlyLimit: 0,
              monthlyUsed: 0,
              monthlyRemaining: 0,
              earnedAvailable: 0,
              periodStart: null,
              periodEnd: null,
            ),
    );
  }
}

int _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

DateTime? _date(Object? v) =>
    (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;
