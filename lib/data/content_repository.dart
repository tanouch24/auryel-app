// Champs privés alimentés par des paramètres nommés publics (même parti pris
// que consultation_controller.dart / wellbeing_controller.dart).
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/content_api.dart';
import 'daily_thought.dart';
import 'meditation_catalog.dart';
import 'meditation_item.dart';

/// Orchestrateur du contenu distant (pensée du jour + méditations) avec cache
/// local et fallback embarqué.
///
/// PRIORITÉ, dans l'ordre :
///   1. réponse serveur valide ;
///   2. cache local (SharedPreferences) ;
///   3. contenu embarqué ([DailyThoughtRepository] / [MeditationCatalog]).
///
/// Ne lève JAMAIS : chaque méthode publique retombe silencieusement sur le
/// niveau suivant. Aucune donnée utilisateur ni secret n'est mis en cache
/// (uniquement du contenu éditorial public).
///
/// Sans [api] / [tokenProvider] (tests hérités, ou app non connectée), le
/// comportement est STRICTEMENT celui du contenu embarqué.
class ContentRepository {
  ContentRepository({
    ContentApi? api,
    Future<String?> Function()? tokenProvider,
    DailyThoughtRepository? embeddedThoughts,
    MeditationCatalog embeddedMeditations = const MeditationCatalog(),
    SharedPreferences? prefs,
  }) : _api = api,
       _token = tokenProvider,
       _embeddedThoughts = embeddedThoughts ?? DailyThoughtRepository(),
       _embeddedMeditations = embeddedMeditations,
       _injectedPrefs = prefs;

  final ContentApi? _api;
  final Future<String?> Function()? _token;
  final DailyThoughtRepository _embeddedThoughts;
  final MeditationCatalog _embeddedMeditations;
  final SharedPreferences? _injectedPrefs;

  static const String _todayKey = 'auryel.content.today.v1';
  static const String _medsKey = 'auryel.content.meditations.v1';

  Future<SharedPreferences> get _prefs async =>
      _injectedPrefs ?? await SharedPreferences.getInstance();

  static String dayString(DateTime now) =>
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';

  // =========================================================================
  // PENSÉE DU JOUR
  // =========================================================================

  /// Pensée du jour pour [now]. Toujours non nulle : au pire, le pack embarqué.
  Future<DailyThought> thoughtFor(DateTime now) async {
    final today = dayString(now);

    final fromServer = await _serverThought();
    if (fromServer != null) {
      await _cacheThought(today, fromServer);
      return fromServer;
    }

    final cached = await _cachedThought(today);
    if (cached != null) return cached;

    return _embeddedThoughts.thoughtFor(now);
  }

  Future<DailyThought> today() => thoughtFor(DateTime.now());

  Future<DailyThought?> _serverThought() async {
    final api = _api;
    if (api == null) return null;
    try {
      final token = await _token?.call();
      final res = await api.today(bearer: token);
      return res?.thought;
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheThought(String day, DailyThought t) async {
    try {
      final p = await _prefs;
      await p.setString(
        _todayKey,
        jsonEncode({
          'date': day,
          'thought': {
            'id': t.id,
            'phrase': t.phrase,
            'interpretation': t.interpretation,
            if (t.imageUrl != null) 'image_url': t.imageUrl,
          },
        }),
      );
    } catch (_) {
      /* cache best-effort */
    }
  }

  Future<DailyThought?> _cachedThought(String day) async {
    try {
      final p = await _prefs;
      final raw = p.getString(_todayKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['date'] != day) return null;
      final t = decoded['thought'];
      return t is Map<String, dynamic>
          ? DailyThought.tryFromServerJson(t)
          : null;
    } catch (_) {
      return null;
    }
  }

  // =========================================================================
  // MÉDITATIONS
  // =========================================================================

  /// Catalogue résolu (serveur -> cache -> embarqué). Peut être vide seulement
  /// si l'embarqué l'est (jamais en pratique).
  Future<List<MeditationItem>> meditations() async {
    final cached = await _readMedsCache();
    final api = _api;

    if (api != null) {
      try {
        final token = await _token?.call();
        final res = await api.meditations(bearer: token, etag: cached?.etag);
        if (res.notModified && cached != null && cached.items.isNotEmpty) {
          return cached.items;
        }
        if (res.ok) {
          if (res.items.isNotEmpty) {
            await _writeMedsCache(res.items, res.etag, res.catalogVersion);
            return res.items;
          }
          // Catalogue serveur VIDE : on ne l'impose pas -> cache puis embarqué.
          if (cached != null && cached.items.isNotEmpty) return cached.items;
          return _embeddedMeditations.all;
        }
        // Autre statut : on retombe sur cache / embarqué ci-dessous.
      } catch (_) {
        /* réseau KO -> cache / embarqué */
      }
    }

    if (cached != null && cached.items.isNotEmpty) return cached.items;
    return _embeddedMeditations.all;
  }

  /// Séance « du jour » — déterministe sur la liste résolue. `null` seulement
  /// si aucune séance n'est disponible (l'écran affiche alors son état propre).
  Future<MeditationItem?> momentOfDay(DateTime now) async {
    final list = await meditations();
    if (list.isEmpty) return null;
    return list[MeditationCatalog.indexForDay(now, list.length)];
  }

  Future<_MedsCache?> _readMedsCache() async {
    try {
      final p = await _prefs;
      final raw = p.getString(_medsKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final rawItems = decoded['items'];
      final items = rawItems is List
          ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(MeditationItem.tryFromJson)
                .whereType<MeditationItem>()
                .toList(growable: false)
          : const <MeditationItem>[];
      return _MedsCache(
        etag: decoded['etag'] as String?,
        version: decoded['catalog_version'] as String?,
        items: items,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeMedsCache(
    List<MeditationItem> items,
    String? etag,
    String? version,
  ) async {
    try {
      final p = await _prefs;
      await p.setString(
        _medsKey,
        jsonEncode({
          'etag': ?etag,
          'catalog_version': ?version,
          'items': [
            for (final it in items)
              {
                'id': it.id,
                'title': it.title,
                'description': it.description,
                if (it.audioUrl != null) 'audio_url': it.audioUrl,
                if (it.assetPath.isNotEmpty) 'asset_path': it.assetPath,
                'duration_seconds': it.duration.inSeconds,
                'category': it.category.name,
              },
          ],
        }),
      );
    } catch (_) {
      /* cache best-effort */
    }
  }
}

@immutable
class _MedsCache {
  const _MedsCache({this.etag, this.version, required this.items});
  final String? etag;
  final String? version;
  final List<MeditationItem> items;
}

/// Fournit le [ContentRepository] à l'arbre. Absent (tests hérités) ->
/// `maybeOf` renvoie `null` et les écrans utilisent leur source embarquée.
class ContentScope extends InheritedWidget {
  const ContentScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final ContentRepository repository;

  static ContentRepository? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentScope>()?.repository;

  @override
  bool updateShouldNotify(ContentScope oldWidget) =>
      oldWidget.repository != repository;
}
