import 'package:flutter/widgets.dart';

/// Index des onglets de [MainNavShell]. Navigation : Accueil · Bien-être ·
/// Consultation · Boutique · Réveil. « Mon compte » QUITTE la
/// barre du bas : accessible depuis le nouvel en-tête bien visible de
/// l'Accueil (voir `home_screen.dart`), qui ouvre directement le Dashboard
/// existant (aucun onglet dédié). (La Boutique n'est plus un onglet V1 — son
/// code reste dans le repo pour plus tard.)
const int kTabHome = 0;
const int kTabBienEtre = 1;
// Alias de compatibilité pour les anciens appels internes. Cet index ouvre
// désormais le Programme Bien-être, jamais l’ancien hub Tirage & Jeu.
const int kTabTirage = kTabBienEtre;
const int kTabConsultation = 2;
const int kTabBoutique = 3;
const int kTabReveil = 4; // Réveil Auryel

/// Compatibilité des routes/deep-links historiques vers le lecteur Méditation.
const int kTabMeditation = kTabBoutique;

/// Permet à un écran (ex. l'Accueil, depuis « Tes missions du jour ») de
/// demander un changement d'onglet SANS reconstruire la barre de navigation, et
/// de connaître l'onglet actuellement visible (utile à l'onglet CONSULTATION
/// pour couper l'audio quand il n'est plus à l'écran — `IndexedStack` garde
/// tous les onglets montés).
class MainNavScope extends InheritedWidget {
  const MainNavScope({
    super.key,
    required this.goToTab,
    required this.currentIndex,
    required super.child,
  });

  final void Function(int index) goToTab;
  final int currentIndex;

  static MainNavScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MainNavScope>();

  @override
  bool updateShouldNotify(MainNavScope oldWidget) =>
      oldWidget.currentIndex != currentIndex;
}
