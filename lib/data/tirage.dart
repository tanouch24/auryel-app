/// Représentation d'un tirage 3 cartes — **réponse canonique du backend**
/// (`POST /api/tirages`, `GET /api/tirages`, `GET /api/tirages/<id>`).
///
/// TIRAGE T3 : la source de vérité pour `name`, `interpretation`,
/// `combinedInterpretation` et `createdAt` est le SERVEUR. Le deck local
/// (`tarot_deck.dart`) ne sert plus qu'à choisir les cartes et à mapper une
/// `key` vers un `assetPath` d'image.
library;

String? _strOrNull(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

DateTime _parseDate(Object? v) {
  if (v is String && v.isNotEmpty) {
    return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

/// Une carte telle que rendue par le serveur (nom + interprétation canoniques).
class TirageCardDto {
  const TirageCardDto({
    required this.key,
    required this.name,
    required this.interpretation,
  });

  final String key;
  final String name;
  final String interpretation;

  factory TirageCardDto.fromJson(Map<String, dynamic> json) => TirageCardDto(
    key: (json['key'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
    interpretation: (json['interpretation'] ?? '').toString(),
  );
}

/// Un tirage sauvegardé, rendu par le serveur. L'ordre de [cardKeys] / [cards]
/// est l'ordre de sélection de l'utilisateur — jamais réordonné.
class TirageResult {
  const TirageResult({
    required this.tirageId,
    required this.cardKeys,
    required this.cards,
    required this.combinedInterpretation,
    this.advisorId,
    this.consultationId,
    required this.createdAt,
  });

  final String tirageId;
  final List<String> cardKeys;
  final List<TirageCardDto> cards;
  final String combinedInterpretation;
  final String? advisorId;
  final String? consultationId;
  final DateTime createdAt;

  factory TirageResult.fromJson(Map<String, dynamic> json) {
    final rawKeys = json['card_keys'];
    final cardKeys = rawKeys is List
        ? rawKeys.map((e) => e.toString()).toList()
        : <String>[];
    final rawCards = json['cards'];
    final cards = rawCards is List
        ? rawCards
              .whereType<Map<String, dynamic>>()
              .map(TirageCardDto.fromJson)
              .toList()
        : <TirageCardDto>[];
    return TirageResult(
      tirageId: (json['tirage_id'] ?? '').toString(),
      cardKeys: cardKeys,
      cards: cards,
      combinedInterpretation: (json['combined_interpretation'] ?? '')
          .toString(),
      advisorId: _strOrNull(json['advisor_id']),
      consultationId: _strOrNull(json['consultation_id']),
      createdAt: _parseDate(json['created_at']),
    );
  }
}

/// Réponse paginée de `GET /api/tirages` — historique « Mon parcours ».
class TirageListResponse {
  const TirageListResponse({required this.tirages, this.nextCursor});

  final List<TirageResult> tirages;
  final String? nextCursor;

  factory TirageListResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['tirages'];
    return TirageListResponse(
      tirages: raw is List
          ? raw
                .whereType<Map<String, dynamic>>()
                .map(TirageResult.fromJson)
                .toList()
          : const [],
      nextCursor: _strOrNull(json['next_cursor']),
    );
  }
}
