import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../notifications/notification_coordinator.dart';
import '../notifications/notification_payload.dart';
import '../notifications/notification_router.dart';
import '../notifications/notification_service.dart';
import '../screens/consultation_screen.dart';
import '../screens/home_screen.dart';
import '../screens/boutique_coming_soon_screen.dart';
import '../screens/wellbeing_program_screen.dart';
import '../screens/wake_settings_screen.dart';
import '../services/app_update_alert.dart';
import '../state/auth_controller.dart';
import '../state/rewards_controller.dart';
import '../state/wellbeing_controller.dart';
import '../state/unread_controller.dart';
import '../theme/auryel_theme.dart';
import 'main_nav_scope.dart';
import '../startup_trace.dart';

export 'main_nav_scope.dart'
    show
        MainNavScope,
        kTabHome,
        kTabBienEtre,
        kTabConsultation,
        kTabBoutique,
        kTabMeditation,
        kTabReveil;

/// Coquille de navigation V2 (CORRECTIF « feed méditation + réveil vocal ») :
/// 5 onglets — Accueil · Bien-être · CONSULTATION · Boutique · RÉVEIL.
/// CONSULTATION est AU CENTRE (index 2) et mise en avant visuellement (icône
/// + relief doré). « Mon compte » QUITTE la barre du bas : accessible depuis
/// le nouvel en-tête de l'Accueil (voir `home_screen.dart`), qui ouvre le
/// Dashboard existant. Le lecteur Méditation reste accessible par ses routes
/// internes et depuis les missions ; la Boutique occupe l'onglet principal.
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

  late final ValueNotifier<String?> _pendingAdvisorId;
  late final List<Widget> _screens;

  // Chaque shell possède ses propres instances d'écran. Une liste statique
  // partageait les mêmes widgets Stateful entre deux montages successifs
  // (notamment après AdultGate), ce qui pouvait laisser un callback
  // d'animation/transformation actif dans la suite Flutter.
  static const _router = NotificationRouter();

  AuryelNotificationService? _notifications;
  StreamSubscription<NotificationPayload>? _openedSub;
  StreamSubscription<NotificationPayload>? _foregroundTapSub;

  /// Destination reçue mais non encore routable (utilisateur pas connecté sur
  /// une cible `requiresAuth`) : rejouée dès que la session devient valide.
  NotificationRoute? _pendingRoute;

  @override
  void initState() {
    super.initState();
    _pendingAdvisorId = ValueNotifier(null);
    _screens = [
      HomeScreen(),
      WellbeingProgramScreen(),
      ConsultationScreen(notificationAdvisorId: _pendingAdvisorId),
      BoutiqueComingSoonScreen(),
      WakeSettingsScreen(),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(AppUpdateAlertService().showIfNeeded(context));
    });
  }

  void _goToTab(int i) {
    if (i < 0 || i >= _screens.length) return;
    final changed = _index != i;
    if (changed) setState(() => _index = i);
    final unread = UnreadScope.maybeReadOf(context);
    if (i == kTabBienEtre) unawaited(unread?.markRead('wellbeing'));
    // La mission « Moment » n'est PLUS cochée à l'ouverture de l'onglet : elle
    // l'est uniquement sur une écoute réellement aboutie (cf. MeditationScreen).
    //
    // AUDIT ACCUEIL/PARCOURS — les onglets restent tous montés (IndexedStack
    // implicite via `_screens`) : revenir sur Accueil ne redéclenche PAS son
    // `initState`. On resynchronise donc explicitement le parcours bien-être
    // partagé au retour sur l'onglet Accueil, pour qu'une mission validée
    // pendant un tirage/une consultation/une méditation se reflète sans
    // jamais fermer/rouvrir l'app.
    if (changed && i == kTabHome) {
      WellbeingScope.maybeReadOf(context)?.refresh();
      // GROS CHANTIER AURYEL (Prompt 2/5) — même logique pour les Étoiles :
      // un tirage/une méditation/un partage effectué dans un autre onglet
      // peut avoir crédité des Étoiles ; le solde du header Accueil doit se
      // refléter sans jamais fermer/rouvrir l'app.
      RewardsScope.maybeReadOf(context)?.refresh();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _notifications ??=
        widget.notificationsOverride ??
        NotificationScope.maybeOf(context)?.service;
    if (_openedSub == null && _notifications != null) {
      _openedSub = _notifications!.onMessageOpened.listen(_handlePayload);
      // Tap sur une notif locale affichée au premier plan (même routage).
      final coordinator = NotificationScope.maybeOf(context)?.coordinator;
      _foregroundTapSub = coordinator?.onNotificationTap.listen(_handlePayload);
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
      if (route.tabIndex == kTabConsultation) {
        final unread = UnreadScope.maybeReadOf(context);
        unread?.noteConsultationAdvisor(route.advisorId);
        _pendingAdvisorId.value = route.advisorId;
        unawaited(unread?.refresh());
      }
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
    if (route.tabIndex == kTabConsultation) {
      final unread = UnreadScope.maybeReadOf(context);
      unread?.noteConsultationAdvisor(route.advisorId);
      _pendingAdvisorId.value = route.advisorId;
      unawaited(unread?.refresh());
      // A notification tap must leave an already-open ChatScreen before the
      // consultation destination is selected. Otherwise the underlying tab
      // changes while the old chat remains visibly on top.
      Navigator.of(context).popUntil((entry) => entry.isFirst);
    }
    _goToTab(route.tabIndex);
  }

  @override
  void dispose() {
    _openedSub?.cancel();
    _foregroundTapSub?.cancel();
    _pendingAdvisorId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    StartupTrace.mark('home/main-nav-build');
    // A shell peut rester sous une route secondaire (Dashboard, chat, etc.).
    // Dans ce cas aucun de ses écrans ne doit continuer à animer : le
    // scheduler Flutter considère toujours ces tickers comme actifs, même
    // lorsqu'ils sont visuellement masqués.
    final routeVisible = ModalRoute.of(context)?.isCurrent ?? true;
    return MainNavScope(
      goToTab: _goToTab,
      currentIndex: _index,
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          // Keep screens mounted so tab state survives, but pause tickers in
          // offstage screens and when the shell is covered by a pushed route.
          children: [
            for (var i = 0; i < _screens.length; i++)
              TickerMode(
                enabled: routeVisible && i == _index,
                child: _screens[i],
              ),
          ],
        ),
        bottomNavigationBar: _AuryelTabBar(
          currentIndex: _index,
          onTap: _goToTab,
          consultationUnread: UnreadScope.maybeOf(context)?.consultation ?? 0,
          wellbeingUnread: UnreadScope.maybeOf(context)?.wellbeing ?? 0,
        ),
      ),
    );
  }
}

class _AuryelTabBar extends StatelessWidget {
  const _AuryelTabBar({
    required this.currentIndex,
    required this.onTap,
    this.consultationUnread = 0,
    this.wellbeingUnread = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int consultationUnread;
  final int wellbeingUnread;

  static const _tabs = [
    (
      label: 'Accueil',
      icon: PhosphorIconsRegular.house,
      activeIcon: PhosphorIconsFill.house,
    ),
    (
      label: 'Bien-être',
      icon: PhosphorIconsRegular.path,
      activeIcon: PhosphorIconsFill.path,
    ),
    (
      label: 'Consultation',
      icon: PhosphorIconsRegular.sparkle,
      activeIcon: PhosphorIconsFill.sparkle,
    ),
    (
      label: 'Boutique',
      icon: PhosphorIconsRegular.storefront,
      activeIcon: PhosphorIconsFill.storefront,
    ),
    (
      label: 'Réveil',
      icon: PhosphorIconsRegular.alarm,
      activeIcon: PhosphorIconsFill.alarm,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('auryel-bottom-tab-bar'),
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

              final unread = i == kTabConsultation
                  ? consultationUnread
                  : i == kTabBienEtre
                  ? wellbeingUnread
                  : 0;
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
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            iconWidget,
                            if (unread > 0)
                              Positioned(
                                right: -8,
                                top: -5,
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AuryelColors.gold,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    '$unread',
                                    textAlign: TextAlign.center,
                                    style: AuryelText.body(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: AuryelColors.backgroundDeep,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: centre ? 2 : 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          // FittedBox : le libellé reste lisible sur 360 dp.
                          // se réduit au lieu d'être coupé ou de déborder à
                          // 360 dp.
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
