import 'package:flutter/widgets.dart';

/// Index des onglets de [MainNavShell] (stables, partagés avec l'Accueil et les
/// tests). Nav V1 finale : Accueil · Tirage & Jeu · CONSULTATION · Méditation ·
/// Mon compte. (La Boutique n'est plus un onglet V1 — son code reste dans le
/// repo pour plus tard.)
const int kTabHome = 0;
const int kTabTirage = 1; // hub « Tirage & Jeu »
const int kTabConsultation = 2;
const int kTabMeditation = 3;
const int kTabCompte = 4; // Dashboard « Mon compte »

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
