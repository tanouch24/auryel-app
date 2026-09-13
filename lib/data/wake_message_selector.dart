import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'wake_message.dart';

/// Historique local des derniers messages du Réveil Auryel RÉELLEMENT
/// sonnés (anti-répétition). Persisté dans SharedPreferences — aucune
/// donnée utilisateur, uniquement des identifiants de contenu éditorial
/// public. Best-effort : toute erreur = historique vide (jamais d'exception).
class WakeMessageHistory {
  WakeMessageHistory({SharedPreferences? prefs, this.keep = 20})
    : _injected = prefs;

  static const String _key = 'auryel.wake_message.history.v1';

  final SharedPreferences? _injected;

  /// Nombre d'identifiants récents conservés (~20 derniers, cf. demande).
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

  Future<void> push(String id) async {
    if (id.isEmpty) return;
    try {
      final list = [...await recent()]..remove(id);
      list.insert(0, id);
      final trimmed = list.take(keep).toList(growable: false);
      await (await _prefs).setString(_key, jsonEncode(trimmed));
    } catch (_) {
      /* best-effort */
    }
  }
}

/// Choisit AUTOMATIQUEMENT un message du Réveil Auryel, au hasard, en évitant
/// de répéter trop vite les derniers sonnés.
///
/// Règles :
///  1. exclure les identifiants récents ([WakeMessageHistory]) tant qu'il
///     reste au moins un candidat ;
///  2. catalogue trop petit (<= historique conservé) -> dégrade proprement :
///     autorise la répétition plutôt que de bloquer le réveil ;
///  3. 1 seul message -> on le prend ; 0 -> `null` (l'appelant garde son
///     dernier message connu, jamais un réveil muet en pratique grâce au
///     repli embarqué de [ContentRepository.wakeMessages]) ;
///  4. le [Random] est injectable pour des tests déterministes.
class WakeMessageSelector {
  WakeMessageSelector({Random? random, WakeMessageHistory? history})
    : _random = random ?? Random(),
      _history = history ?? WakeMessageHistory();

  final Random _random;
  final WakeMessageHistory _history;

  /// Sélection pure (sans historique) — testable sans I/O. [avoid] liste les
  /// identifiants à éviter si possible.
  WakeMessage? choose(List<WakeMessage> catalog, {List<String> avoid = const []}) {
    if (catalog.isEmpty) return null;
    if (catalog.length == 1) return catalog.first;

    final avoidSet = avoid.toSet();
    final fresh = catalog
        .where((m) => !avoidSet.contains(m.id))
        .toList(growable: false);
    final candidates = fresh.isNotEmpty ? fresh : catalog; // répétition tolérée
    return candidates[_random.nextInt(candidates.length)];
  }

  /// Sélection complète : lit l'historique, choisit, puis met à jour
  /// l'historique avec le message retenu.
  Future<WakeMessage?> pick(List<WakeMessage> catalog) async {
    final recent = await _history.recent();
    final picked = choose(catalog, avoid: recent);
    if (picked != null) await _history.push(picked.id);
    return picked;
  }
}
