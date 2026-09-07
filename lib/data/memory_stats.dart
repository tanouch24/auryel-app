import 'package:shared_preferences/shared_preferences.dart';

import 'memory_game.dart';

/// Statistiques LUDIQUES et LOCALES du Jeu Auryel (SharedPreferences).
///
/// Conserve : nombre de parties terminées, meilleur temps par niveau, niveaux
/// déjà joués. RIEN d'autre : aucune seconde de consultation, aucune récompense,
/// aucun crédit — ce store n'a aucun moyen d'en accorder et ne doit jamais
/// être présenté comme une source de récompense.
class MemoryStats {
  MemoryStats({SharedPreferences? prefs}) : _injected = prefs;

  final SharedPreferences? _injected;

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  static const _kGamesCompleted = 'auryel.memory.games_completed';
  static String _kBest(GameDifficulty d) => 'auryel.memory.best_ms.${d.name}';
  static String _kPlayed(GameDifficulty d) => 'auryel.memory.played.${d.name}';

  Future<int> gamesCompleted() async =>
      (await _prefs).getInt(_kGamesCompleted) ?? 0;

  /// Meilleur temps enregistré pour [d], ou `null` si aucune partie terminée.
  Future<Duration?> bestTime(GameDifficulty d) async {
    final ms = (await _prefs).getInt(_kBest(d));
    return ms == null ? null : Duration(milliseconds: ms);
  }

  Future<bool> hasPlayed(GameDifficulty d) async =>
      (await _prefs).getBool(_kPlayed(d)) ?? false;

  /// Enregistre une partie terminée. Renvoie `true` si [time] est un nouveau
  /// meilleur temps pour ce niveau.
  Future<bool> recordCompletion(GameDifficulty d, Duration time) async {
    final prefs = await _prefs;
    await prefs.setInt(_kGamesCompleted, (await gamesCompleted()) + 1);
    await prefs.setBool(_kPlayed(d), true);
    final prevMs = prefs.getInt(_kBest(d));
    if (prevMs == null || time.inMilliseconds < prevMs) {
      await prefs.setInt(_kBest(d), time.inMilliseconds);
      return true;
    }
    return false;
  }

  /// Marque un niveau comme « déjà joué » dès le lancement d'une partie.
  Future<void> markStarted(GameDifficulty d) async {
    await (await _prefs).setBool(_kPlayed(d), true);
  }
}
