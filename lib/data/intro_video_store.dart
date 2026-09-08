import 'package:shared_preferences/shared_preferences.dart';

/// Vue d'intro Auryel — flag LOCAL « la vidéo d'introduction a déjà été vue ».
///
/// Purement local (`SharedPreferences`), aucun backend. La vidéo ne se joue
/// qu'AVANT le tout premier onboarding ; une fois vue (fin naturelle ou
/// « Passer »), elle ne revient jamais. Même mécanique d'injection que
/// `DailyLikeStore` pour les tests.
class IntroVideoStore {
  IntroVideoStore({SharedPreferences? prefs}) : _injected = prefs;

  static const String key = 'auryel.intro_video_seen.v1';

  final SharedPreferences? _injected;
  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  Future<bool> hasSeen() async {
    try {
      final prefs = await _prefs;
      return prefs.getBool(key) ?? false;
    } catch (_) {
      // En cas de souci de stockage : on considère « vue » pour ne jamais
      // bloquer l'utilisateur derrière une vidéo qui reviendrait en boucle.
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

  /// Tests / reset DEBUG ciblé : oublie que la vidéo a été vue.
  Future<void> reset() async {
    try {
      final prefs = await _prefs;
      await prefs.remove(key);
    } catch (_) {
      /* best-effort */
    }
  }
}

/// Étape de démarrage à afficher après le splash.
enum IntroStep {
  /// Vidéo d'intro Auryel, puis onboarding.
  video,

  /// Parcours d'onboarding directement (prénom → … → compte).
  onboarding,

  /// Onboarding déjà terminé : routage auth habituel (accueil / connexion).
  authRouting,
}

/// Décision PURE (testable sans widget ni plugin vidéo).
///
/// Priorité :
///  1. onboarding terminé            → [IntroStep.authRouting] (jamais de vidéo)
///  2. sinon, vidéo déjà vue         → [IntroStep.onboarding]
///  3. sinon                         → [IntroStep.video]
class IntroGate {
  const IntroGate._();

  static IntroStep decide({
    required bool onboardingCompleted,
    required bool introVideoSeen,
  }) {
    if (onboardingCompleted) return IntroStep.authRouting;
    if (introVideoSeen) return IntroStep.onboarding;
    return IntroStep.video;
  }
}
