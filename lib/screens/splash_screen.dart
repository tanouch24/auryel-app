import 'dart:async';

import 'package:flutter/material.dart';

import '../data/intro_video_store.dart';
import '../data/wake_video.dart';
import '../services/wake_alarm_channel.dart';
import '../state/auryel_state.dart';
import '../state/auth_controller.dart';
import '../state/consultation_controller.dart';
import '../state/profile_restore.dart';
import '../state/session_profile_gate.dart';
import '../state/rewards_controller.dart';
import '../state/wellbeing_controller.dart';
import '../state/wellbeing_program_controller.dart';
import '../state/wellbeing_ebooks_controller.dart';
import '../theme/auryel_theme.dart';
import '../startup_trace.dart';
import 'adult_gate.dart';
import 'intro_video_screen.dart';
import 'onboarding/email_auth_screen.dart';
import 'onboarding/first_name_screen.dart';
import 'wake_ringing_screen.dart';

/// Pont de démarrage Flutter entre le splash natif et le premier écran utile.
///
/// Le splash système Android porte l'identité de lancement. Cet écran ne
/// réaffiche donc aucun logo : il garde uniquement le fond Auryel pendant la
/// restauration asynchrone de session, puis route vers la présentation ou
/// l'application. Cela évite la séquence native → wordmark Flutter → vidéo
/// d'introduction, qui donnait l'impression d'un double lancement.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.wakeAlarmChannel});

  /// Test uniquement : pont natif du Réveil Auryel injecté (aucun canal
  /// plateforme réel en test).
  final WakeAlarmChannel? wakeAlarmChannel;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final WakeAlarmChannel _wakeChannel =
      widget.wakeAlarmChannel ?? MethodChannelWakeAlarm();
  @override
  void initState() {
    super.initState();
    StartupTrace.mark('splash/initState');
    // Après la première frame : le contexte peut alors résoudre les scopes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StartupTrace.mark('splash/first-frame');
      _boot();
    });
  }

  Future<void> _boot() async {
    StartupTrace.mark('splash/boot-start');
    // La durée du splash natif dépend du démarrage réel. Aucune temporisation
    // artificielle : la présentation apparaît dès que le routage est prêt.
    final auth = AuthScope.of(context);
    final consultation = ConsultationScope.of(context);
    final wellbeing = WellbeingScope.maybeOf(context);
    final wellbeingProgram = WellbeingProgramScope.maybeOf(context);
    final wellbeingEbooks = WellbeingEbooksScope.maybeOf(context);
    final rewards = RewardsScope.maybeOf(context);
    final introSeenFuture = IntroVideoStore().hasSeen();
    StartupTrace.mark('splash/restore-start');
    await auth.restoreFast();
    StartupTrace.mark('auth/local-restore-finished:${auth.status.name}');
    final introSeen = await introSeenFuture;
    StartupTrace.mark('storage/intro-read');
    if (!mounted) return;
    // Resynchro de l'état consultation UNIQUEMENT une fois la session restaurée
    // et valide (le GET /state exige un Bearer). Lecture seule : aucun POST,
    // aucun crédit consommé.
    //
    // AUDIT ABONNEMENT (corrigé) : ce `refreshAll()` reste délibérément
    // `unawaited` — l'attendre bloquerait le splash (et donc l'entrée dans
    // l'app) sur un réseau lent ou absent, ce qui serait pire que la race
    // qu'on évite ici. La stratégie retenue est plutôt l'option « garantir
    // que tous les écrans consommateurs sont réactifs » : `HomeScreen`,
    // `PremiumScreen` et `DashboardScreen` (les 3 écrans qui affichent
    // `quota.isPremium`) écoutent tous activement
    // `ConsultationController` (`ListenableBuilder` / `Listenable.merge`).
    // Donc même si un écran s'ouvre AVANT que ce refresh ait résolu (et lit
    // transitoirement `quota == null` -> `isPremium: false` via les replis
    // `?? false`), il se reconstruit automatiquement dès que la réponse
    // serveur arrive — « non Premium » n'y est jamais un état terminal, juste
    // transitoire. Hors ligne, le dernier état vérifié du même compte peut
    // être présenté ; le backend reste l'autorité des actions protégées.
    if (auth.isSignedIn) {
      // Portefeuille (`/state`) + liste des consultations (`/list`, J6-F2).
      unawaited(consultation.restoreLastKnownState());
      unawaited(consultation.refreshAll());
      // AUDIT ACCUEIL/PARCOURS — même logique non bloquante : Accueil et
      // « Mon parcours bien-être » écoutent la MÊME instance partagée
      // (WellbeingScope) et se reconstruisent dès que cette réponse arrive.
      if (wellbeing != null) unawaited(wellbeing.refresh());
      if (wellbeingProgram != null) unawaited(wellbeingProgram.refresh());
      if (wellbeingEbooks != null) unawaited(wellbeingEbooks.refresh());
      // GROS CHANTIER AURYEL (Prompt 2/5) — ÉTOILES : même logique non
      // bloquante, même instance partagée (RewardsScope).
      if (rewards != null) unawaited(rewards.refresh());
    }
    StartupTrace.mark('refreshes/scheduled');
    // MULTI-APPAREIL — au démarrage avec session valide, si le profil local est
    // absent / incomplet / rattaché à un autre compte, on récupère le profil
    // serveur réel avant d'entrer dans l'app.
    unawaited(_maybeRestoreProfile(auth));
    StartupTrace.mark('profile/restore-scheduled');
    if (!mounted) return;
    _goToNext(auth, introSeen: introSeen);
  }

  /// Récupère le profil serveur AU DÉMARRAGE uniquement si nécessaire — un
  /// profil local complet et du bon `userId` évite tout appel réseau (démarrage
  /// rapide). Ne déconnecte jamais sur erreur réseau/5xx ; sur 401,
  /// `AuthController` bascule en `sessionExpired` et [_goToNext] route vers le
  /// login. Aucune donnée d'un autre compte n'est affichée (oubli local avant
  /// fetch si `userId` diffère).
  Future<void> _maybeRestoreProfile(AuthController auth) async {
    // Pas de fetch en mode dégradé (networkError) : démarrage hors ligne, on
    // s'appuie sur le dernier profil local valide.
    if (auth.status != AuthStatus.signedIn) return;
    final account = auth.account;
    if (account == null || account.userId.isEmpty) return;
    final state = AuryelStateScope.of(context);

    // Profil local complet ET du bon compte -> démarrage direct, aucun appel.
    if (SessionProfileGate.localProfileUsableAsIs(
      accountUserId: account.userId,
      localUserId: state.userId,
      firstName: state.firstName,
      birthDate: state.birthDate,
      selectedAdvisor: state.selectedAdvisor,
    )) {
      return;
    }

    if (SessionProfileGate.mustForgetLocalIdentity(
      accountUserId: account.userId,
      localUserId: state.userId,
    )) {
      await state.forgetLocalIdentity();
      if (!mounted) return;
    }

    final restore = await auth.fetchServerProfile();
    if (!mounted) return;
    final profile = restore.profile;
    if (profile != null) {
      await applyServerProfileToState(state, profile);
    }
  }

  static Route<void> _fadeRoute(Widget page) => PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );

  void _goToNext(AuthController auth, {required bool introSeen}) {
    if (!mounted) return;
    final onboardingCompleted = AuryelStateScope.of(context)
        .onboardingCompleted;
    final navigator = Navigator.of(context);

    // Priorité : onboarding terminé -> jamais de vidéo ; sinon vidéo déjà vue
    // -> onboarding direct ; sinon -> vidéo d'intro puis onboarding.
    final step = IntroGate.decide(
      onboardingCompleted: onboardingCompleted,
      introVideoSeen: introSeen,
    );
    StartupTrace.mark('router/decision:${step.name}');

    final Widget next;
    switch (step) {
      case IntroStep.video:
        next = IntroVideoScreen(
          onDone: () =>
              navigator.pushReplacement(_fadeRoute(const FirstNameScreen())),
        );
      case IntroStep.onboarding:
        // Parcours d'onboarding depuis le début : prénom (1/5), date de
        // naissance (2/5), « parle-moi de toi » (3/5), conseiller (4/5),
        // création du compte (5/5, email + mot de passe — AUCUN code OTP).
        next = const FirstNameScreen();
      case IntroStep.authRouting:
        // Onboarding terminé : SEUL un vrai jeton donne accès à l'app.
        // Un onboarding local terminé et/ou un ancien `temp_xxx` ne comptent
        // jamais comme une authentification.
        bool enteringApp;
        switch (auth.status) {
          case AuthStatus.signedIn:
          case AuthStatus.networkError:
            // Jeton présent et accepté, OU présent mais backend momentanément
            // injoignable (jeton conservé) → accueil, éventuellement en mode
            // dégradé/offline.
            next = const AdultGate();
            enteringApp = true;
          case AuthStatus.signedOut:
          case AuthStatus.sessionExpired:
          case AuthStatus.unknown:
            // Aucun jeton, ou jeton rejeté en 401 (déjà purgé) → connexion.
            next = const EmailAuthScreen();
            enteringApp = false;
        }
        navigator.pushReplacement(_fadeRoute(next));
        StartupTrace.mark('router/home-route-pushed');
        // RÉVEIL AURYEL — l'app a été (re)lancée par le déclenchement natif
        // de l'alarme (notification plein écran / activité directe) : on
        // affiche l'écran de sonnerie PAR-DESSUS l'app normale, jamais à la
        // place de l'écran de connexion (un conseiller nécessite une session
        // valide). Consommé une seule fois côté natif -> jamais réaffiché
        // sans une nouvelle sonnerie réelle.
        if (enteringApp) unawaited(_maybeShowWakeRinging(navigator));
        return;
    }

    navigator.pushReplacement(_fadeRoute(next));
  }

  Future<void> _maybeShowWakeRinging(NavigatorState navigator) async {
    final details = await _wakeChannel.consumeWakeRingingLaunchDetails();
    if (details == null && !await _wakeChannel.consumeWakeRingingLaunch()) {
      return;
    }
    final video = details == null
        ? WakeVideoCatalog.pilot
        : WakeVideo.tryFromJson({
            'id': details['wakeVideoId'],
            'video_url': details['wakeVideoUrl'],
            'title': details['wakeVideoTitle'],
          });
    if (!mounted) return;
    navigator.push(
      MaterialPageRoute(
        builder: (_) =>
            WakeRingingScreen(video: video ?? WakeVideoCatalog.pilot),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(gradient: AuryelColors.backgroundGradient),
      child: SizedBox.expand(),
    );
  }
}
