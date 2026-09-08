import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../notifications/notification_coordinator.dart';
import '../notifications/notification_payload.dart';
import '../notifications/notification_router.dart';
import '../notifications/notification_service.dart';
import '../screens/consultation_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/home_screen.dart';
import '../screens/meditation_screen.dart';
import '../screens/tirage_jeu_screen.dart';
import '../state/auth_controller.dart';
import '../theme/auryel_theme.dart';
import 'main_nav_scope.dart';

export 'main_nav_scope.dart'
    show
        MainNavScope,
        kTabHome,
        kTabTirage,
        kTabConsultation,
        kTabMeditation,
        kTabCompte;

/// Coquille de navigation V1 finale : 5 onglets — Accueil · Tirage & Jeu ·
/// CONSULTATION · Méditation · Mon compte. CONSULTATION est AU CENTRE
/// (index 2) et mise en avant visuellement (icône + relief doré). « Mon
/// compte » réutilise le Dashboard existant (sans flèche retour). La Boutique
/// n'est plus un onglet V1 (son code reste dans le repo pour plus tard).
class MainNavShell extends StatefulWidget {
  const MainNavShell({super.key, this.notificationsOverride});

  /// Test uniquement : service de notifications injecté (sinon lu depuis
  /// [NotificationScope], sinon aucun traitement).
  final AuryelNotificationService? notificationsOverride;

  @override
  State<MainNavShell> createState() => _MainNavShellState();
}

class _MainNavShellState extends State<MainNavShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    TirageJeuScreen(),
    ConsultationScreen(),
    MeditationScreen(),
    DashboardScreen(showBackButton: false),
  ];

  static const _router = NotificationRouter();

  AuryelNotificationService? _notifications;
  StreamSubscription<NotificationPayload>? _openedSub;

  /// Destination reçue mais non encore routable (utilisateur pas connecté sur
  /// une cible `requiresAuth`) : rejouée dès que la session devient valide.
  NotificationRoute? _pendingRoute;

  void _goToTab(int i) {
    if (i < 0 || i >= _screens.length) return;
    if (_index != i) setState(() => _index = i);
    // La mission « Moment » n'est PLUS cochée à l'ouverture de l'onglet : elle
    // l'est uniquement sur une écoute réellement aboutie (cf. MeditationScreen).
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _notifications ??=
        widget.notificationsOverride ??
        NotificationScope.maybeOf(context)?.service;
    if (_openedSub == null && _notifications != null) {
      _openedSub = _notifications!.onMessageOpened.listen(_handlePayload);
      // Notification ayant lancé l'app depuis un état terminé — traitée
      // maintenant que la navigation est prête (consommation unique).
      final initial = _notifications!.takeInitialPayload();
      if (initial != null) _handlePayload(initial);
    }
    // Une session redevenue valide -> on rejoue une éventuelle destination
    // différée (ex. personal_guidance reçue hors connexion).
    if (_pendingRoute != null && _isSignedIn) {
      final route = _pendingRoute!;
      _pendingRoute = null;
      _goToTab(route.tabIndex);
    }
  }

  bool get _isSignedIn => AuthScope.maybeOf(context)?.isSignedIn ?? true;

  /// Traduit un payload en changement d'onglet. Cible inconnue -> rien. Cible
  /// `requiresAuth` alors que l'utilisateur n'est pas connecté -> différée
  /// (jamais poussé de force dans Consultation). JAMAIS la Boutique.
  void _handlePayload(NotificationPayload payload) {
    final route = _router.routeForPayload(payload);
    if (route == null || !mounted) return;
    if (route.requiresAuth && !_isSignedIn) {
      _pendingRoute = route;
      return;
    }
    _goToTab(route.tabIndex);
  }

  @override
  void dispose() {
    _openedSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MainNavScope(
      goToTab: _goToTab,
      currentIndex: _index,
      child: Scaffold(
        body: IndexedStack(index: _index, children: _screens),
        bottomNavigationBar: _AuryelTabBar(
          currentIndex: _index,
          onTap: _goToTab,
        ),
      ),
    );
  }
}

class _AuryelTabBar extends StatelessWidget {
  const _AuryelTabBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _tabs = [
    (
      label: 'Accueil',
      icon: PhosphorIconsRegular.house,
      activeIcon: PhosphorIconsFill.house,
    ),
    (
      label: 'Tirage & Jeu',
      icon: PhosphorIconsRegular.cardsThree,
      activeIcon: PhosphorIconsFill.cardsThree,
    ),
    (
      label: 'Consultation',
      icon: PhosphorIconsRegular.sparkle,
      activeIcon: PhosphorIconsFill.sparkle,
    ),
    (
      label: 'Méditation',
      icon: PhosphorIconsRegular.flowerLotus,
      activeIcon: PhosphorIconsFill.flowerLotus,
    ),
    (
      label: 'Mon compte',
      icon: PhosphorIconsRegular.userCircle,
      activeIcon: PhosphorIconsFill.userCircle,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AuryelColors.surface,
        border: Border(
          top: BorderSide(color: AuryelColors.warmBorder, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(_tabs.length, (i) {
              final tab = _tabs[i];
              final active = i == currentIndex;
              final centre = i == kTabConsultation;
              final color = active ? AuryelColors.gold : AuryelColors.textMuted;
              final iconSize = centre ? 26.0 : 22.0;

              final iconWidget = centre
                  ? Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AuryelColors.gold.withValues(
                          alpha: active ? 0.20 : 0.12,
                        ),
                        border: Border.all(
                          color: AuryelColors.goldLight.withValues(
                            alpha: active ? 0.85 : 0.5,
                          ),
                          width: 1.2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: PhosphorIcon(
                        active ? tab.activeIcon : tab.icon,
                        size: iconSize,
                        color: active
                            ? AuryelColors.goldLight
                            : AuryelColors.gold,
                      ),
                    )
                  : PhosphorIcon(
                      active ? tab.activeIcon : tab.icon,
                      size: iconSize,
                      color: color,
                    );

              return Expanded(
                child: Semantics(
                  button: true,
                  selected: active,
                  label: tab.label,
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        iconWidget,
                        SizedBox(height: centre ? 2 : 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          // FittedBox : les libellés longs (« Tirage & Jeu »,
                          // « Mon compte ») se réduisent au lieu d'être coupés
                          // ou de déborder à 360 dp.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              tab.label,
                              maxLines: 1,
                              softWrap: false,
                              style: AuryelText.body(
                                fontSize: centre ? 10 : 10.5,
                                fontWeight: (active || centre)
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: centre && !active
                                    ? AuryelColors.gold
                                    : color,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
