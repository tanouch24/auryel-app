import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'relaxation_video.dart';

/// Historique local des dernières vidéos d'ambiance affichées (anti-répétition).
/// Persisté dans SharedPreferences — aucune donnée utilisateur, uniquement des
/// slugs de contenu éditorial public. Best-effort : toute erreur = historique
/// vide (jamais d'exception).
class RelaxationVideoHistory {
  RelaxationVideoHistory({SharedPreferences? prefs, this.keep = 3})
    : _injected = prefs;

  static const String _key = 'auryel.relaxation.video_history.v1';

  final SharedPreferences? _injected;

  /// Nombre de slugs récents conservés (et donc exclus du prochain tirage tant
  /// que le catalogue le permet).
  final int keep;

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  Future<List<String>> recent() async {
    try {
      final raw = (await _prefs).getString(_key);
      if (raw == null) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> push(String slug) async {
    if (slug.isEmpty) return;
    try {
      final list = [...await recent()]..remove(slug);
      list.insert(0, slug);
      final trimmed = list.take(keep).toList(growable: false);
      await (await _prefs).setString(_key, jsonEncode(trimmed));
    } catch (_) {
      /* best-effort */
    }
  }
}

/// Choisit AUTOMATIQUEMENT une vidéo d'ambiance compatible avec une méditation,
/// au hasard, en évitant de répéter les dernières affichées.
///
/// Règles :
///  1. filtrer les vidéos compatibles avec la catégorie de la méditation
///     (une vidéo générique passe toujours) ;
///  2. si aucune compatible -> repli sur TOUT le catalogue actif ;
///  3. exclure les slugs récents ([RelaxationVideoHistory]) tant qu'il reste
///     au moins un candidat ; sinon (catalogue ≤ historique) autoriser la
///     répétition « intelligente » ;
///  4. 1 seule vidéo -> on la prend ; 0 -> `null` (l'écran garde un fond
///     statique) ;
///  5. le [Random] est injectable pour des tests déterministes.
class RelaxationVideoSelector {
  RelaxationVideoSelector({Random? random, RelaxationVideoHistory? history})
    : _random = random ?? Random(),
      _history = history ?? RelaxationVideoHistory();

  final Random _random;
  final RelaxationVideoHistory _history;

  /// Sélection pure (sans historique) — testable sans I/O. [avoid] liste les
  /// slugs à éviter si possible.
  RelaxationVideo? choose(
    List<RelaxationVideo> catalog, {
    required String meditationCategory,
    List<String> avoid = const [],
  }) {
    if (catalog.isEmpty) return null;

    var pool = catalog
        .where((v) => v.isCompatibleWith(meditationCategory))
        .toList(growable: false);
    if (pool.isEmpty) pool = catalog; // repli générique

    if (pool.length == 1) return pool.first;

    final avoidSet = avoid.toSet();
    final fresh = pool
        .where((v) => !avoidSet.contains(v.slug))
        .toList(growable: false);
    final candidates = fresh.isNotEmpty ? fresh : pool; // répétition tolérée

    return candidates[_random.nextInt(candidates.length)];
  }

  /// Sélection complète : lit l'historique, choisit, puis met l'historique à
  /// jour avec la vidéo retenue.
  Future<RelaxationVideo?> pick(
    List<RelaxationVideo> catalog, {
    required String meditationCategory,
  }) async {
    final recent = await _history.recent();
    final picked = choose(
      catalog,
      meditationCategory: meditationCategory,
      avoid: recent,
    );
    if (picked != null) await _history.push(picked.slug);
    return picked;
  }
}
