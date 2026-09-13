import 'package:flutter/widgets.dart';

/// Signale à une page de [MeditationFeedScreen] (feed vertical) si ELLE est
/// la page actuellement active (visible/au premier plan). `MeditationScreen`
/// s'appuie dessus, EN PLUS de la vérification d'onglet existante
/// ([MainNavScope]), pour mettre en pause son audio/vidéo dès qu'une AUTRE
/// page du feed devient active — jamais de double audio entre deux pages.
///
/// Absent (écran ouvert seul, hors feed, comme depuis un ancien appelant) ->
/// [isActive] vaut toujours `true` : comportement historique inchangé.
class FeedPageScope extends InheritedWidget {
  const FeedPageScope({
    super.key,
    required this.pageIndex,
    required this.activeIndex,
    required super.child,
  });

  final int pageIndex;
  final int activeIndex;

  bool get isActive => pageIndex == activeIndex;

  static FeedPageScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeedPageScope>();

  @override
  bool updateShouldNotify(FeedPageScope oldWidget) =>
      oldWidget.activeIndex != activeIndex || oldWidget.pageIndex != pageIndex;
}
