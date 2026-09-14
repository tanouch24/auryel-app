/// Types logiques de notification Auryel. La valeur `wire` est celle envoyée
/// par le backend dans `data.type`. Toute valeur absente/inconnue -> [unknown]
/// (ignorée proprement, jamais de crash).
enum NotificationType {
  dailyThought(wire: 'daily_thought'),
  dailyMeditation(wire: 'daily_meditation'),
  personalGuidance(wire: 'personal_guidance'),
  weeklySleep(wire: 'weekly_sleep'),
  weeklyLifeLesson(wire: 'weekly_life_lesson'),
  ebookMonthly(wire: 'ebook_monthly'),
  unknown(wire: '');

  const NotificationType({required this.wire});

  final String wire;

  static NotificationType fromWire(String? raw) {
    final v = (raw ?? '').trim();
    for (final t in NotificationType.values) {
      if (t != NotificationType.unknown && t.wire == v) return t;
    }
    return NotificationType.unknown;
  }
}

/// Charge utile normalisée d'une notification. Seul [type] compte pour le
/// routing V1 ; les autres champs sont facultatifs et tolérants (une clé
/// absente ou d'un type inattendu est ignorée, jamais une exception).
class NotificationPayload {
  const NotificationPayload({
    required this.type,
    this.title,
    this.body,
    this.consultationId,
    this.advisor,
    this.contentId,
    this.raw = const {},
  });

  final NotificationType type;
  final String? title;
  final String? body;
  final String? consultationId;
  final String? advisor;
  final String? contentId;

  /// Données brutes reçues (diagnostic / évolutions). Jamais loggées telles
  /// quelles en production.
  final Map<String, Object?> raw;

  bool get isActionable => type != NotificationType.unknown;

  /// Construit depuis le bloc `data` d'un message FCM (ou tout `Map` équivalent).
  /// `null` / map vide -> payload [NotificationType.unknown] (aucun crash).
  factory NotificationPayload.fromData(Map<String, Object?>? data) {
    final d = data ?? const <String, Object?>{};
    String? str(String key) {
      final v = d[key];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return NotificationPayload(
      type: NotificationType.fromWire(str('type')),
      title: str('title'),
      body: str('body'),
      consultationId: str('consultation_id'),
      advisor: str('advisor'),
      contentId: str('content_id'),
      raw: Map<String, Object?>.unmodifiable(d),
    );
  }

  @override
  String toString() => 'NotificationPayload(${type.name})';
}
