/// Portefeuille de temps de consultation renvoyé par le backend (bloc `time`
/// de `GET /api/consultation/state`, `POST /api/consultation/message` et du
/// corps d'un 402 `time_exhausted`).
///
/// TIMER-D.1 — c'est désormais LA SOURCE DE VÉRITÉ du temps disponible :
///   - `totalRemainingSeconds` = temps total exploitable (somme des buckets)
///   - `firstFree/premium/earned/purchased` = détail par bucket (1 h offerte /
///     Premium par période / temps gagné via le parcours / heures achetées).
///     Ordre de débit backend : first_free -> premium -> earned -> purchased.
///   - `windowActive` / `windowExpiresAt` = fenêtre d'activité de 5 min (le
///     backend facture le temps par tranche de 5 min ; cette fenêtre ne
///     détermine PAS si la consultation est « finie »).
///
/// On ne dérive JAMAIS le temps de `expiresAt - now` : `expiresAt` n'est plus
/// qu'une valeur de compat backend.
class ConsultationTimeState {
  const ConsultationTimeState({
    required this.firstFreeRemainingSeconds,
    required this.premiumRemainingSeconds,
    required this.purchasedRemainingSeconds,
    required this.totalRemainingSeconds,
    required this.windowActive,
    required this.windowExpiresAt,
    this.earnedRemainingSeconds = 0,
  });

  final int firstFreeRemainingSeconds;
  final int premiumRemainingSeconds;

  /// Temps gagné via le parcours bien-être (`earned_remaining_seconds`). Champ
  /// absent d'un backend ancien -> 0.
  final int earnedRemainingSeconds;
  final int purchasedRemainingSeconds;
  final int totalRemainingSeconds;
  final bool windowActive;
  final DateTime? windowExpiresAt;

  /// État « aucun temps » (utilisé pour un 402 `time_exhausted` sans bloc
  /// `time` exploitable, ou comme valeur neutre).
  static const empty = ConsultationTimeState(
    firstFreeRemainingSeconds: 0,
    premiumRemainingSeconds: 0,
    earnedRemainingSeconds: 0,
    purchasedRemainingSeconds: 0,
    totalRemainingSeconds: 0,
    windowActive: false,
    windowExpiresAt: null,
  );

  bool get hasTime => totalRemainingSeconds > 0;

  /// Somme des buckets (first_free + premium + earned + purchased) — filet si
  /// le backend n'envoie pas `total`.
  int get bucketSum =>
      firstFreeRemainingSeconds +
      premiumRemainingSeconds +
      earnedRemainingSeconds +
      purchasedRemainingSeconds;

  factory ConsultationTimeState.fromJson(Map<String, dynamic> json) {
    // A short-lived production compatibility response used
    // `welcome_seconds`/`welcome_remaining_seconds` for the same server
    // bucket. Accept those aliases only when the canonical key is absent;
    // the backend remains the authority and no welcome time is invented.
    final firstFreeRaw = json.containsKey('first_free_remaining_seconds')
        ? json['first_free_remaining_seconds']
        : (json.containsKey('welcome_remaining_seconds')
              ? json['welcome_remaining_seconds']
              : json['welcome_seconds']);
    final ff = _clampPos(_int(firstFreeRaw));
    final pr = _clampPos(_int(json['premium_remaining_seconds']));
    final ea = _clampPos(_int(json['earned_remaining_seconds']));
    final pu = _clampPos(_int(json['purchased_remaining_seconds']));
    final total = json.containsKey('total_remaining_seconds')
        ? _clampPos(_int(json['total_remaining_seconds']))
        : ff + pr + ea + pu;
    return ConsultationTimeState(
      firstFreeRemainingSeconds: ff,
      premiumRemainingSeconds: pr,
      earnedRemainingSeconds: ea,
      purchasedRemainingSeconds: pu,
      totalRemainingSeconds: total,
      windowActive: json['window_active'] == true,
      windowExpiresAt: _date(json['window_expires_at']),
    );
  }

  /// `null` quand la clé `time` est absente / n'est pas un objet : le backend
  /// distant peut être ANCIEN (avant le déploiement coordonné du modèle
  /// temps). L'appelant applique alors son fallback legacy — il ne doit PAS
  /// interpréter ça comme « 0 seconde ». Après le déploiement coordonné, le
  /// bloc `time` est toujours présent.
  static ConsultationTimeState? maybeFromJson(Object? raw) =>
      raw is Map<String, dynamic> ? ConsultationTimeState.fromJson(raw) : null;
}

/// DTO d'une consultation renvoyée par `POST /api/consultation/message` /
/// `GET /api/consultation/state`.
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
  /// pendant la session, prime sur le conseiller du profil. Pendant une
  /// fenêtre d'activité, le backend FIGE ce conseiller même si le préféré
  /// local a changé : ne jamais présumer que c'est le préféré local.
  final String advisorId;
  final DateTime? startedAt;

  /// TIMER-D.1 — COMPAT UNIQUEMENT. Le backend renvoie encore `expires_at`
  /// (colonne NOT NULL, valeur = `started_at + 2 h`) mais elle n'est PLUS un
  /// cutoff : ne jamais l'utiliser pour décider si la consultation est active
  /// ni pour calculer le temps restant.
  final DateTime? expiresAt;

  /// TIMER-D.1 — vaut désormais `time.total_remaining_seconds` (portefeuille
  /// de temps TOTAL, tous buckets), et non plus `expiresAt - now`. Pas de
  /// décompte local seconde par seconde sur ce total.
  final int secondsRemaining;

  /// `"time"` pour une consultation ouverte par le moteur temps.
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

/// J6 — résumé d'un fil de discussion pour l'écran « Consultations en cours »
/// (`GET /api/consultation/list`). Modèle V1 : UN fil par conseiller.
///
/// Parsing tolérant : `id` et `advisor_id` sont REQUIS (une entrée sans eux est
/// inexploitable) ; `started_at` / `last_activity_at` ne sont parsés que s'ils
/// portent une date valide ; `preview` absent / vide -> `null` (jamais de
/// crash). `window_active` faux par défaut.
class ConsultationSummaryDto {
  const ConsultationSummaryDto({
    required this.id,
    required this.advisorId,
    required this.startedAt,
    required this.lastActivityAt,
    required this.windowActive,
    required this.preview,
  });

  final String id;
  final String advisorId;
  final DateTime? startedAt;
  final DateTime? lastActivityAt;
  final bool windowActive;

  /// Extrait du dernier message du fil — `null` si le backend n'en fournit pas.
  final String? preview;

  /// `null` si l'entrée est inexploitable (`id` ou `advisor_id` absent) : la
  /// couche API filtre alors la ligne au lieu de lever (même esprit que
  /// [ConsultationMessagesResponse.fromJson]).
  static ConsultationSummaryDto? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = (raw['id'] ?? '').toString();
    final advisorId = (raw['advisor_id'] ?? '').toString();
    if (id.isEmpty || advisorId.isEmpty) return null;
    final preview = raw['preview'];
    return ConsultationSummaryDto(
      id: id,
      advisorId: advisorId,
      startedAt: _date(raw['started_at']),
      lastActivityAt: _date(raw['last_activity_at']),
      windowActive: raw['window_active'] == true,
      preview: (preview is String && preview.isNotEmpty) ? preview : null,
    );
  }

  /// Liste depuis le corps `{ "consultations": [ … ] }`. Les entrées
  /// inexploitables (voir [tryFromJson]) sont ignorées.
  static List<ConsultationSummaryDto> listFromJson(Map<String, dynamic> json) {
    final raw = json['consultations'];
    if (raw is! List) return const [];
    return raw
        .map(ConsultationSummaryDto.tryFromJson)
        .whereType<ConsultationSummaryDto>()
        .toList(growable: false);
  }
}

/// Un message d'historique renvoyé par `GET /api/consultation/messages`.
class ConsultationMessageDto {
  const ConsultationMessageDto({
    required this.role,
    required this.content,
    required this.timestamp,
    this.messageId,
    this.llmStatus,
  });

  /// `user` ou `assistant`. Toute autre valeur est traitée côté UI comme
  /// « conseiller » (bulle gauche) — jamais comme un message utilisateur.
  final String role;
  final String content;
  final DateTime? timestamp;

  /// Identifiant stable du message côté backend (`message_id`, ou `id` en
  /// repli). `null` pour une réponse ANCIENNE d'un backend qui ne l'expose pas
  /// encore — l'UI reste fonctionnelle, le signalement retombe sur le
  /// `consultation_id`.
  final String? messageId;

  /// `llm_status` — état de génération LLM de la réponse assistant (ex.
  /// `ok`, `fallback`, `error`). `null` si absent / non pertinent (message
  /// utilisateur, backend ancien).
  final String? llmStatus;

  bool get isUser => role == 'user';

  factory ConsultationMessageDto.fromJson(Map<String, dynamic> json) =>
      ConsultationMessageDto(
        role: (json['role'] ?? '').toString(),
        content: (json['content'] ?? '').toString(),
        timestamp: _date(json['timestamp']),
        messageId: _str(json['message_id']) ?? _str(json['id']),
        llmStatus: _str(json['llm_status']),
      );
}

/// Réponse 200 de `GET /api/consultation/messages`. Lecture seule : aucun
/// crédit consommé, aucun appel LLM, aucun POST. `consultationId` vaut `null`
/// quand le backend n'a aucune consultation rattachée à renvoyer.
class ConsultationMessagesResponse {
  const ConsultationMessagesResponse({
    required this.consultationId,
    required this.messages,
  });

  final String? consultationId;
  final List<ConsultationMessageDto> messages;

  factory ConsultationMessagesResponse.fromJson(Map<String, dynamic> json) {
    final rawId = json['consultation_id'];
    final rawList = json['messages'];
    return ConsultationMessagesResponse(
      consultationId: (rawId is String && rawId.isNotEmpty) ? rawId : null,
      messages: rawList is List
          ? rawList
                .whereType<Map<String, dynamic>>()
                .map(ConsultationMessageDto.fromJson)
                .toList(growable: false)
          : const [],
    );
  }
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

  /// SHIM DE COMPAT UI. `monthlyLimit` vaut 8 = HEURES Premium / mois, PAS un
  /// nombre de consultations. `monthlyRemaining` / `monthlyUsed` ne pilotent
  /// PLUS l'accès au chat (c'est `ConsultationTimeState.totalRemainingSeconds`
  /// qui décide). Gardé parsé pour les écrans existants uniquement.
  static const empty = QuotaDto(
    isPremium: false,
    monthlyLimit: 0,
    monthlyUsed: 0,
    monthlyRemaining: 0,
    earnedAvailable: 0,
    periodStart: null,
    periodEnd: null,
  );

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
    this.time,
    this.replyMessageId,
    this.llmStatus,
  });

  final String reply;
  final ConsultationDto? consultation;
  final QuotaDto quota;

  /// TIMER-D.1 — bloc `time` (source de vérité). `null` si le backend distant
  /// est encore ancien (fallback legacy côté contrôleur).
  final ConsultationTimeState? time;

  /// Identifiant stable de LA réponse assistant renvoyée dans `reply`. Sert à
  /// cibler le signalement (`POST /api/app/ai/report { message_id }`).
  ///
  /// Parsing TOLÉRANT : `message_id` à la racine, sinon `message.message_id` /
  /// `message.id` si le backend imbrique la réponse dans un objet `message`.
  /// `null` si aucune de ces formes n'est présente (backend ancien) — le
  /// signalement retombe alors sur `consultation_id`.
  final String? replyMessageId;

  /// `llm_status` de la réponse assistant (racine ou `message.llm_status`).
  /// `null` si absent.
  final String? llmStatus;

  factory ConsultationMessageResponse.fromJson(Map<String, dynamic> json) {
    final c = json['consultation'];
    final q = json['quota'];
    final m = json['message'];
    final msg = m is Map<String, dynamic> ? m : const <String, dynamic>{};
    return ConsultationMessageResponse(
      reply: (json['reply'] ?? '').toString(),
      consultation: c is Map<String, dynamic>
          ? ConsultationDto.fromJson(c)
          : null,
      quota: q is Map<String, dynamic> ? QuotaDto.fromJson(q) : QuotaDto.empty,
      time: ConsultationTimeState.maybeFromJson(json['time']),
      replyMessageId:
          _str(json['message_id']) ??
          _str(msg['message_id']) ??
          _str(msg['id']),
      llmStatus: _str(json['llm_status']) ?? _str(msg['llm_status']),
    );
  }
}

/// Réponse 200 de `GET /api/consultation/state` (F4). Lecture seule : aucun
/// crédit consommé, `consultation` vaut `null` s'il n'y a pas de session active.
class ConsultationStateResponse {
  const ConsultationStateResponse({
    required this.consultation,
    required this.quota,
    this.time,
  });

  final ConsultationDto? consultation;
  final QuotaDto quota;

  /// TIMER-D.1 — bloc `time` (source de vérité). `null` si backend ancien.
  final ConsultationTimeState? time;

  factory ConsultationStateResponse.fromJson(Map<String, dynamic> json) {
    final c = json['consultation'];
    final q = json['quota'];
    return ConsultationStateResponse(
      consultation: c is Map<String, dynamic>
          ? ConsultationDto.fromJson(c)
          : null,
      quota: q is Map<String, dynamic> ? QuotaDto.fromJson(q) : QuotaDto.empty,
      time: ConsultationTimeState.maybeFromJson(json['time']),
    );
  }
}

int _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

int _clampPos(int v) => v < 0 ? 0 : v;

DateTime? _date(Object? v) =>
    (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;

/// Chaîne non vide, sinon `null`. Fail-safe : n'accepte QUE des `String`
/// (les identifiants backend en sont), jamais de coercion depuis un nombre /
/// objet.
String? _str(Object? v) => (v is String && v.isNotEmpty) ? v : null;
