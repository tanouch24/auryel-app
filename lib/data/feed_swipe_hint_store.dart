import 'package:shared_preferences/shared_preferences.dart';

/// Persiste si l'indication de swipe du feed Méditation
/// (« Fais glisser pour découvrir une autre méditation ») a déjà été montrée —
/// UNE SEULE fois, à travers les sessions (pas seulement la session en
/// cours) : jamais gênante après le tout premier vrai swipe de l'utilisateur.
class FeedSwipeHintStore {
  const FeedSwipeHintStore();

  static const _key = 'auryel.meditation_feed.swipe_hint_seen.v1';

  Future<bool> hasBeenShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {
      // Repli prudent : en cas d'erreur de lecture, on préfère ne PAS
      // ré-afficher une indication déjà vue plutôt que d'être gênant.
      return true;
    }
  }

  Future<void> markShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {
      /* non bloquant */
    }
  }
}
