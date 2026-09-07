import 'package:shared_preferences/shared_preferences.dart';

/// Nettoyage des données LOCALES rattachées au compte, à n'invoquer QU'APRÈS un
/// succès serveur de suppression de compte (cf. [AccountDeletionService]).
///
/// SÉPARATION EXPLICITE (auditée) :
///
///  DONNÉES PERSONNELLES / LIÉES AU COMPTE  -> supprimées ici :
///   - `auryel_onboarding_v1`     (**identité locale** : prénom, date de
///                                 naissance, conseiller préféré, portrait —
///                                 la donnée la plus sensible sur l'appareil)
///   - `auryel.daily_mission.*`   (dates des missions du jour)
///   - `auryel.daily_share.days`  (jours de partage — progression récompense)
///   - `auryel.daily_like.*.days` (contenus aimés : messages, tirages)
///   - `auryel.memory.*`          (stats du Jeu Auryel : parties, meilleurs temps)
///   - `auryel.experience_intro_seen.v1` / `auryel.intro_video_seen.v1`
///                                (un nouveau compte doit revoir l'intro)
///   - `auryel.shop_cart.v1`      (panier local — repart vide)
///
///  PRÉFÉRENCES APPAREIL, NON PERSONNELLES -> CONSERVÉES :
///   - `auryel.consultation.audio_muted.v1`
///                                (choix d'ergonomie de l'appareil, aucun lien
///                                 avec l'identité ; le réinitialiser n'apporte
///                                 rien et surprend l'utilisateur suivant)
///
///  Le JETON de session n'est PAS géré ici : il vit dans le stockage chiffré de
///  l'OS ([TokenStore]) et est purgé séparément par [AccountDeletionService].
///
///  L'IDENTIFIANT D'INSTALLATION (`auryel_installation_id_v1`,
///  [InstallationIdStore]) n'est PAS géré ici non plus : c'est un signal
///  anti-abus lié à l'installation, pas au compte — il vit dans le stockage
///  chiffré (jamais `SharedPreferences`) et doit être CONSERVÉ après une
///  suppression de compte. `clearPersonal()` ne touche que `SharedPreferences`,
///  donc il ne l'atteint jamais.
class LocalUserData {
  LocalUserData({SharedPreferences? prefs}) : _injected = prefs;

  final SharedPreferences? _injected;

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  /// Préfixes / clés exactes des données personnelles locales.
  static const List<String> _personalExactKeys = [
    // Identité locale (prénom / date de naissance / conseiller / portrait).
    'auryel_onboarding_v1',
    'auryel.daily_share.days',
    'auryel.experience_intro_seen.v1',
    'auryel.intro_video_seen.v1',
    'auryel.shop_cart.v1',
    'auryel.memory.games_completed',
  ];

  static const List<String> _personalPrefixes = [
    'auryel.daily_mission.',
    'auryel.daily_like.',
    'auryel.memory.best_ms.',
    'auryel.memory.played.',
  ];

  /// Clés/prefixes explicitement CONSERVÉS (préférences appareil).
  static const List<String> keptDeviceKeys = [
    'auryel.consultation.audio_muted.v1',
  ];

  /// Supprime toutes les données personnelles locales. Idempotent, ne touche
  /// jamais [keptDeviceKeys].
  Future<void> clearPersonal() async {
    final prefs = await _prefs;
    final toRemove = <String>{};
    for (final k in prefs.getKeys()) {
      if (keptDeviceKeys.contains(k)) continue;
      if (_personalExactKeys.contains(k) ||
          _personalPrefixes.any(k.startsWith)) {
        toRemove.add(k);
      }
    }
    for (final k in toRemove) {
      await prefs.remove(k);
    }
  }
}
