import 'package:shared_preferences/shared_preferences.dart';

/// Flag LOCAL « l'écran de présentation "Bienvenue dans Auryel" a déjà été vu
/// automatiquement ».
///
/// Purement local (`SharedPreferences`), aucun backend. Distinct du flag de la
/// vidéo d'intro ([`auryel.intro_video_seen.v1`]) : cet écran arrive APRÈS la
/// création de compte + la synchro du profil, une seule fois. Il reste
/// rejouable manuellement depuis le Dashboard SANS toucher ce flag.
class ExperienceIntroStore {
  ExperienceIntroStore({SharedPreferences? prefs}) : _injected = prefs;

  static const String key = 'auryel.experience_intro_seen.v1';

  final SharedPreferences? _injected;
  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  Future<bool> hasSeen() async {
    try {
      final prefs = await _prefs;
      return prefs.getBool(key) ?? false;
    } catch (_) {
      // Souci de stockage : on considère « vu » pour ne jamais bloquer
      // l'utilisateur derrière un écran de présentation qui reviendrait.
      return true;
    }
  }

  Future<void> markSeen() async {
    try {
      final prefs = await _prefs;
      await prefs.setBool(key, true);
    } catch (_) {
      /* best-effort */
    }
  }

  /// Tests / reset DEBUG ciblé.
  Future<void> reset() async {
    try {
      final prefs = await _prefs;
      await prefs.remove(key);
    } catch (_) {
      /* best-effort */
    }
  }
}
