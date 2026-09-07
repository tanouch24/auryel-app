import '../data/app_profile.dart';
import '../widgets/advisors_carousel.dart';
import 'auryel_state.dart';

/// Adaptateur unique `AppProfile` (serveur) -> [AuryelState].
///
/// Résout le conseiller préféré via l'UNIQUE mapping [advisorByGuideKey]
/// (`guide` backend `selena`… -> nom accentué `Séléna`…), `null` si le guide
/// est inconnu — aucun repli silencieux, aucun choix fabriqué. La règle de
/// source de vérité (« le serveur prime dès qu'il renvoie une valeur ; un vide
/// serveur ne remplace pas le local ») vit dans [AuryelState.applyServerProfile].
///
/// Partagé par le flux LOGIN (`EmailAuthScreen`) et la RESTAURATION DE SESSION
/// (`SplashScreen`) : une seule copie de la logique d'injection.
Future<void> applyServerProfileToState(AuryelState state, AppProfile profile) {
  final prenom = profile.prenom.trim();
  return state.applyServerProfile(
    userId: profile.userId,
    firstName: prenom.isEmpty ? null : prenom,
    birthDate: profile.birthDateOrNull,
    advisorName: advisorByGuideKey(profile.guide)?.name,
  );
}
