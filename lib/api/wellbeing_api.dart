import 'api_client.dart';

/// Un niveau du parcours bien-être (paliers 5 / 10 / 15 / 20 / 25 / 30 jours
/// DANS le cycle courant). Wording NON médical, figé côté serveur.
const List<(int, String)> kWellbeingLevels = [
  (5, 'Élan'),
  (10, 'Ancrage'),
  (15, 'Harmonie'),
  (20, 'Sérénité'),
  (25, 'Équilibre'),
  (30, 'Rayonnement'),
];

/// Les 4 missions quotidiennes réelles d'Auryel, dans l'ordre serveur.
const List<String> kWellbeingMissions = [
  'pensee',
  'tirage',
  'consultation',
  'moment',
];

/// Une mission du jour + son statut.
class WellbeingMission {
  const WellbeingMission({required this.id, required this.completed});

  final String id;
  final bool completed;

  factory WellbeingMission.fromJson(Map<String, dynamic> json) =>
      WellbeingMission(
        id: (json['id'] ?? '').toString(),
        completed: json['completed'] == true,
      );
}

/// Journée en cours du parcours.
class WellbeingToday {
  const WellbeingToday({
    required this.date,
    required this.missions,
    required this.completed,
  });

  /// `YYYY-MM-DD` (jour Europe/Paris, décidé par le serveur).
  final String date;
  final List<WellbeingMission> missions;

  /// `true` quand les 4 missions du jour sont accomplies.
  final bool completed;

  factory WellbeingToday.fromJson(Map<String, dynamic> json) {
    final raw = json['missions'];
    final list = raw is List
        ? raw
              .whereType<Map<String, dynamic>>()
              .map(WellbeingMission.fromJson)
              .toList(growable: false)
        : const <WellbeingMission>[];
    return WellbeingToday(
      date: (json['date'] ?? '').toString(),
      missions: list,
      completed: json['completed'] == true,
    );
  }

  WellbeingMission? mission(String id) {
    for (final m in missions) {
      if (m.id == id) return m;
    }
    return null;
  }
}

/// Progression du parcours bien-être — RÉPONSE SERVEUR, source de vérité.
/// Aucun compteur local ne fait autorité : la progression et la récompense
/// survivent à la fermeture de l'app, à la déconnexion et au changement
/// d'appareil.
class WellbeingProgress {
  const WellbeingProgress({
    required this.completedDaysTotal,
    required this.cycleCompletedDays,
    required this.currentLevel,
    required this.nextLevel,
    required this.daysToNextLevel,
    required this.today,
    required this.cycleNumber,
    required this.rewardEarnedForCurrentCycle,
    required this.rewardCreditedNow,
    required this.rewardCreditedSeconds,
  });

  /// Journées ENTIÈREMENT complétées, tous cycles confondus.
  final int completedDaysTotal;

  /// Journées complétées DANS le cycle courant (0..30).
  final int cycleCompletedDays;

  /// Niveau actuellement atteint dans le cycle (`null` avant le 1er palier).
  final String? currentLevel;

  /// Prochain niveau visé (`null` à Rayonnement).
  final String? nextLevel;

  /// Journées restantes avant [nextLevel] (0 à Rayonnement).
  final int daysToNextLevel;

  final WellbeingToday today;

  /// Numéro du cycle de 30 journées en cours (1, 2, 3, …).
  final int cycleNumber;

  /// `true` si la récompense (+15 min) du cycle courant a déjà été créditée.
  final bool rewardEarnedForCurrentCycle;

  /// `true` UNIQUEMENT quand la réponse à un `recordMission` vient d'accorder
  /// le crédit (bloc `reward` du POST). Toujours `false` pour un GET.
  final bool rewardCreditedNow;

  /// Secondes créditées lors de CET appel (900 au palier, 0 sinon). Jamais
  /// utilisé pour modifier un solde côté client : on rafraîchit le portefeuille
  /// depuis le serveur.
  final int rewardCreditedSeconds;

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static String? _asStrOrNull(Object? v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  factory WellbeingProgress.fromJson(Map<String, dynamic> json) {
    final reward = json['reward'];
    final rewardMap = reward is Map<String, dynamic> ? reward : const {};
    final todayRaw = json['today'];
    return WellbeingProgress(
      completedDaysTotal: _asInt(json['completed_days_total']),
      cycleCompletedDays: _asInt(json['cycle_completed_days']),
      currentLevel: _asStrOrNull(json['current_level']),
      nextLevel: _asStrOrNull(json['next_level']),
      daysToNextLevel: _asInt(json['days_to_next_level']),
      today: WellbeingToday.fromJson(
        todayRaw is Map<String, dynamic> ? todayRaw : const {},
      ),
      cycleNumber: () {
        final n = _asInt(json['cycle_number']);
        return n > 0 ? n : 1;
      }(),
      rewardEarnedForCurrentCycle:
          json['reward_earned_for_current_cycle'] == true,
      rewardCreditedNow: rewardMap['credited'] == true,
      rewardCreditedSeconds: _asInt(rewardMap['credited_seconds']),
    );
  }

  /// Palier du cycle (30 journées).
  static int get cycleTarget => kWellbeingLevels.last.$1;
}

/// Levée par [WellbeingApi.recordMission] quand le serveur refuse une mission
/// dérivée dont l'action réelle n'a pas eu lieu aujourd'hui (HTTP 409). La
/// progression n'est PAS modifiée — l'utilisateur doit d'abord réaliser
/// l'activité correspondante.
class WellbeingMissionActionMissing implements Exception {
  const WellbeingMissionActionMissing(this.missionId);
  final String missionId;
  @override
  String toString() => 'WellbeingMissionActionMissing($missionId)';
}

/// Parcours bien-être côté app. Réutilise l'[ApiClient] commun — aucun second
/// client HTTP.
///
///   GET  /api/app/wellbeing/progress   (Bearer) -> WellbeingProgress
///     Lecture seule. Ne récompense jamais.
///   POST /api/app/wellbeing/mission    (Bearer) { "mission_id" } -> WellbeingProgress
///     Enregistre l'accomplissement d'UNE mission pour aujourd'hui. `moment`
///     est enregistrée (aucune trace serveur) ; `pensee` / `tirage` /
///     `consultation` sont vérifiées contre leur trace réelle (409 sinon).
///     Le serveur crédite +900 s à la 30e journée d'un cycle, une fois.
class WellbeingApi {
  WellbeingApi(this._client);

  final ApiClient _client;

  Future<WellbeingProgress> getProgress(String bearer) async {
    final json = await _client.getJson(
      '/api/app/wellbeing/progress',
      bearer: bearer,
    );
    return WellbeingProgress.fromJson(json);
  }

  Future<WellbeingProgress> recordMission({
    required String bearer,
    required String missionId,
  }) async {
    try {
      final json = await _client.postJson('/api/app/wellbeing/mission', {
        'mission_id': missionId,
      }, bearer: bearer);
      return WellbeingProgress.fromJson(json);
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        throw WellbeingMissionActionMissing(missionId);
      }
      rethrow;
    }
  }
}
