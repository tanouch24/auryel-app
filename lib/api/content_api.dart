import '../data/daily_thought.dart';
import '../data/meditation_item.dart';
import 'api_client.dart';

/// Contenu du jour renvoyé par `GET /api/app/content/today`.
///
/// `thought` et la publication sont NULLABLES : le backend peut n'avoir rien
/// de publié pour sa date serveur (Europe/Paris). `serverDate` sert à
/// rattacher le cache local à la bonne journée.
class TodayContent {
  const TodayContent({
    this.serverDate,
    this.thought,
    this.publicationImageUrl,
    this.publicationText,
  });

  final String? serverDate;
  final DailyThought? thought;
  final String? publicationImageUrl;
  final String? publicationText;

  factory TodayContent.fromJson(Map<String, dynamic> json) {
    final rawThought = json['daily_thought'];
    final rawPub = json['daily_publication'];
    return TodayContent(
      serverDate: _str(json['date']),
      thought: rawThought is Map<String, dynamic>
          ? DailyThought.tryFromServerJson(rawThought)
          : null,
      publicationImageUrl: rawPub is Map<String, dynamic>
          ? _str(rawPub['image_url'])
          : null,
      publicationText: rawPub is Map<String, dynamic>
          ? _str(rawPub['text'])
          : null,
    );
  }
}

/// Résultat de `GET /api/app/content/meditations` (catalogue conditionnel).
///
///  - `status == 304` -> l'appelant CONSERVE son cache (pas une erreur).
///  - `status == 200` -> `items` = catalogue actif (peut être VIDE si le
///    backend n'a encore rien publié) + `catalogVersion` + `etag`.
///  - autre -> `items` vide, à l'appelant de retomber sur cache / embarqué.
class MeditationsCatalogResult {
  const MeditationsCatalogResult({
    required this.status,
    required this.items,
    this.catalogVersion,
    this.etag,
  });

  final int status;
  final List<MeditationItem> items;
  final String? catalogVersion;
  final String? etag;

  bool get notModified => status == 304;
  bool get ok => status == 200;
}

/// Couche API du contenu distant (pensée du jour + méditations). Réutilise
/// l'[ApiClient] commun (aucun second client HTTP) via [ApiClient.getRaw] pour
/// exploiter l'`ETag` / le `304`.
class ContentApi {
  ContentApi(this._client);

  final ApiClient _client;

  /// `null` si le backend répond hors-2xx (le contenu distant ne doit jamais
  /// bloquer l'app) ; une [ApiUnauthorizedException] / [ApiNetworkException]
  /// remonte comme pour les autres appels — l'appelant l'absorbe.
  Future<TodayContent?> today({String? bearer}) async {
    final res = await _client.getRaw('/api/app/content/today', bearer: bearer);
    if (!res.ok) return null;
    return TodayContent.fromJson(res.body);
  }

  /// `etag` : dernier `ETag` connu -> envoyé en `If-None-Match`. Un `304`
  /// renvoie `MeditationsCatalogResult(status: 304, items: [])`.
  Future<MeditationsCatalogResult> meditations({
    String? bearer,
    String? etag,
  }) async {
    final res = await _client.getRaw(
      '/api/app/content/meditations',
      bearer: bearer,
      ifNoneMatch: etag,
    );
    if (res.notModified) {
      return MeditationsCatalogResult(status: 304, items: const [], etag: etag);
    }
    if (!res.ok) {
      return MeditationsCatalogResult(status: res.statusCode, items: const []);
    }
    final rawItems = res.body['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(MeditationItem.tryFromJson)
              .whereType<MeditationItem>()
              .toList(growable: false)
        : const <MeditationItem>[];
    return MeditationsCatalogResult(
      status: 200,
      items: items,
      catalogVersion: _str(res.body['catalog_version']),
      etag: res.etag ?? etag,
    );
  }
}

String? _str(Object? v) => (v is String && v.isNotEmpty) ? v : null;
