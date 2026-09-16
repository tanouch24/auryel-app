import '../data/daily_thought.dart';
import '../data/exercise.dart';
import '../data/meditation_item.dart';
import '../data/relaxation_video.dart';
import '../data/wake_message.dart';
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
///
/// Contrat serveur réel : `{ "version", "catalog_version", "meditations": [...] }`.
/// La clé historique `items` est encore acceptée en repli (compat ascendante).
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

/// Résultat de `GET /api/app/content/relaxation-videos` (catalogue conditionnel,
/// même philosophie que [MeditationsCatalogResult]).
///
///  - `status == 304` -> l'appelant CONSERVE son cache (pas une erreur).
///  - `status == 200` -> `videos` = catalogue actif (peut être VIDE) +
///    `catalogVersion` + `etag`.
///  - autre -> `videos` vide : l'app retombe sur cache / fond statique. Une
///    absence de vidéo ne bloque JAMAIS une méditation.
class RelaxationVideosResult {
  const RelaxationVideosResult({
    required this.status,
    required this.videos,
    this.catalogVersion,
    this.etag,
  });

  final int status;
  final List<RelaxationVideo> videos;
  final String? catalogVersion;
  final String? etag;

  bool get notModified => status == 304;
  bool get ok => status == 200;
}

/// Catalogue des MP4 de méditation R2. Il est distinct des vidéos d'ambiance
/// historiques utilisées par le Réveil et par l'ancien lecteur audio.
class MeditationVideosResult {
  const MeditationVideosResult({
    required this.status,
    required this.videos,
    this.catalogVersion,
    this.etag,
  });

  final int status;
  final List<RelaxationVideo> videos;
  final String? catalogVersion;
  final String? etag;

  bool get notModified => status == 304;
  bool get ok => status == 200;
}

/// Résultat de `GET /api/app/content/wake-messages` (catalogue conditionnel,
/// même philosophie que [RelaxationVideosResult]).
///
///  - `status == 304` -> l'appelant CONSERVE son cache (pas une erreur).
///  - `status == 200` -> `messages` = liste active (peut être VIDE) +
///    `catalogVersion` + `etag`.
///  - autre -> `messages` vide : l'app retombe sur cache local / repli
///    embarqué. Une absence de message ne bloque JAMAIS le réveil.
class WakeMessagesResult {
  const WakeMessagesResult({
    required this.status,
    required this.messages,
    this.catalogVersion,
    this.etag,
  });

  final int status;
  final List<WakeMessage> messages;
  final String? catalogVersion;
  final String? etag;

  bool get notModified => status == 304;
  bool get ok => status == 200;
}

class ExercisesResult {
  const ExercisesResult({
    required this.status,
    required this.exercises,
    this.catalogVersion,
    this.etag,
  });

  final int status;
  final List<Exercise> exercises;
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

  Future<ExercisesResult> exercises({String? bearer, String? etag}) async {
    final res = await _client.getRaw(
      '/api/app/content/exercises',
      bearer: bearer,
      ifNoneMatch: etag,
    );
    if (res.notModified) {
      return ExercisesResult(status: 304, exercises: const [], etag: etag);
    }
    if (!res.ok) {
      return ExercisesResult(status: res.statusCode, exercises: const []);
    }
    final raw = res.body['exercises'] ?? res.body['items'];
    final exercises = raw is List
        ? raw
              .map(Exercise.tryFromJson)
              .whereType<Exercise>()
              .toList(growable: false)
        : const <Exercise>[];
    return ExercisesResult(
      status: 200,
      exercises: exercises,
      catalogVersion: _str(res.body['catalog_version']),
      etag: res.etag ?? etag,
    );
  }

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
    // Contrat serveur : clé `meditations`. `items` = repli pour une éventuelle
    // ancienne réponse.
    final rawItems = res.body['meditations'] ?? res.body['items'];
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

  /// Catalogue vidéo demandé via le même endpoint historique, avec une
  /// représentation explicite `media=video`. Le backend conserve ainsi la
  /// compatibilité du catalogue audio par défaut.
  Future<MeditationVideosResult> meditationVideos({
    String? bearer,
    String? etag,
  }) async {
    final res = await _client.getRaw(
      '/api/app/content/meditations?media=video',
      bearer: bearer,
      ifNoneMatch: etag,
    );
    if (res.notModified) {
      return MeditationVideosResult(status: 304, videos: const [], etag: etag);
    }
    if (!res.ok) {
      return MeditationVideosResult(status: res.statusCode, videos: const []);
    }
    final rawItems = res.body['meditation_videos'];
    final videos = rawItems is List
        ? rawItems
              .whereType<Map<String, dynamic>>()
              .where((item) {
                final key = item['object_key'];
                return key is String &&
                    (key.startsWith('meditations/') ||
                        key.startsWith('méditations/')) &&
                    key.toLowerCase().endsWith('.mp4');
              })
              .map(RelaxationVideo.tryFromJson)
              .whereType<RelaxationVideo>()
              .toList(growable: false)
        : const <RelaxationVideo>[];
    return MeditationVideosResult(
      status: 200,
      videos: videos,
      catalogVersion: _str(res.body['catalog_version']),
      etag: res.etag ?? etag,
    );
  }

  /// Catalogue des vidéos d'ambiance. Même contrat que [meditations] :
  /// `etag` -> `If-None-Match`, `304` -> `RelaxationVideosResult(status: 304)`.
  /// Ne bloque jamais l'app : un statut hors-2xx renvoie une liste vide.
  Future<RelaxationVideosResult> relaxationVideos({
    String? bearer,
    String? etag,
  }) async {
    final res = await _client.getRaw(
      '/api/app/content/relaxation-videos',
      bearer: bearer,
      ifNoneMatch: etag,
    );
    if (res.notModified) {
      return RelaxationVideosResult(status: 304, videos: const [], etag: etag);
    }
    if (!res.ok) {
      return RelaxationVideosResult(status: res.statusCode, videos: const []);
    }
    final raw = res.body['videos'];
    final videos = raw is List
        ? raw
              .whereType<Map<String, dynamic>>()
              .map(RelaxationVideo.tryFromJson)
              .whereType<RelaxationVideo>()
              .toList(growable: false)
        : const <RelaxationVideo>[];
    return RelaxationVideosResult(
      status: 200,
      videos: videos,
      catalogVersion: _str(res.body['catalog_version']),
      etag: res.etag ?? etag,
    );
  }

  /// Messages du Réveil Auryel. Même contrat que [relaxationVideos] : `etag`
  /// -> `If-None-Match`, `304` -> `WakeMessagesResult(status: 304)`. Ne
  /// bloque jamais l'app : un statut hors-2xx renvoie une liste vide (repli
  /// cache local / embarqué côté appelant).
  Future<WakeMessagesResult> wakeMessages({
    String? bearer,
    String? etag,
  }) async {
    final res = await _client.getRaw(
      '/api/app/content/wake-messages',
      bearer: bearer,
      ifNoneMatch: etag,
    );
    if (res.notModified) {
      return WakeMessagesResult(status: 304, messages: const [], etag: etag);
    }
    if (!res.ok) {
      return WakeMessagesResult(status: res.statusCode, messages: const []);
    }
    final raw = res.body['messages'];
    final messages = raw is List
        ? raw
              .whereType<Map<String, dynamic>>()
              .map(WakeMessage.tryFromJson)
              .whereType<WakeMessage>()
              .toList(growable: false)
        : const <WakeMessage>[];
    return WakeMessagesResult(
      status: 200,
      messages: messages,
      catalogVersion: _str(res.body['catalog_version']),
      etag: res.etag ?? etag,
    );
  }
}

String? _str(Object? v) => (v is String && v.isNotEmpty) ? v : null;
