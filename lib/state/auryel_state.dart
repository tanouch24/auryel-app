import 'dart:math';

import 'package:flutter/widgets.dart';

import '../data/onboarding_record.dart';
import '../data/onboarding_repository.dart';
import 'auth_controller.dart' show ProfileSyncOutcome;

/// Synchronise le conseiller préféré côté backend (`PATCH /api/app/profile`,
/// champ `guide` seul). Injecté depuis `main()` (branché sur
/// `AuthController.syncGuide`) ; `null` dans les tests / avant l'auth.
typedef GuideSyncFn = Future<ProfileSyncOutcome> Function(String guideKey);

/// Issue d'un [AuryelState.changeAdvisor].
enum AdvisorChangeOutcome {
  /// Le conseiller demandé est déjà le conseiller préféré — aucun appel, rien
  /// à faire.
  unchanged,

  /// Backend mis à jour PUIS persistance locale : local et serveur alignés.
  synced,

  /// Aucune synchro backend branchée (tests) : changement local + persistance.
  localOnly,

  /// `PATCH` en échec réseau / 5xx : RIEN n'a changé (ni local, ni serveur) —
  /// aucun état incohérent, l'utilisateur peut réessayer.
  networkFailed,

  /// `PATCH` rejeté en 401 : session invalidée, aucun changement local.
  unauthorized,
}

/// État partagé de l'appli — identité + progression onboarding. Le
/// `userId` est `null` tant que le compte (mock) n'a pas été "créé" ; ce
/// n'est jamais l'email qui sert d'identité technique, seulement ce
/// `userId` interne (le futur backend utilisera un `user_id` Auryel réel).
class AuryelState extends ChangeNotifier {
  AuryelState({
    required this.repository,
    OnboardingRecord? initial,
    this.guideSync,
  }) : userId = initial?.userId,
       selectedAdvisor = initial?.selectedAdvisor,
       firstName = initial?.firstName,
       birthDate = initial?.birthDate,
       portraitData = initial?.portraitData,
       portraitFeedback = initial?.portraitFeedback,
       onboardingCompleted = initial?.onboardingCompleted ?? false;

  final OnboardingRepository repository;

  /// Cf. [GuideSyncFn]. `null` => pas de synchro backend (mode test / pré-auth).
  final GuideSyncFn? guideSync;

  String? userId;
  String? selectedAdvisor;
  String? firstName;
  DateTime? birthDate;
  String? portraitData;
  String? portraitFeedback;
  bool onboardingCompleted;

  /// Onboarding uniquement — sélection en cours de parcours. La persistance a
  /// lieu plus tard, à [completeOnboarding]. Pour un changement APRÈS
  /// l'onboarding, utiliser [changeAdvisor] (persiste + synchronise).
  void selectAdvisor(String advisorName) {
    selectedAdvisor = advisorName;
    notifyListeners();
  }

  /// UX-B §4-§8 — change le conseiller PRÉFÉRÉ après l'onboarding.
  ///
  /// Stratégie retenue (sûre, sans divergence local/serveur) : on synchronise
  /// le backend D'ABORD (`PATCH /api/app/profile { guide }`), et on ne touche
  /// l'état local + `SharedPreferences` QU'APRÈS un succès. En cas d'échec
  /// réseau / 401, rien ne bouge — l'appelant affiche un message et
  /// l'utilisateur peut réessayer.
  ///
  /// N'ouvre AUCUNE consultation, ne consomme AUCUN crédit, ne modifie JAMAIS
  /// l'`advisor_id` d'une consultation active : ce changement ne concerne que
  /// la PROCHAINE consultation.
  Future<AdvisorChangeOutcome> changeAdvisor(
    String advisorName,
    String guideKey,
  ) async {
    if (advisorName == selectedAdvisor) {
      return AdvisorChangeOutcome.unchanged;
    }

    final sync = guideSync;
    if (sync != null) {
      final outcome = await sync(guideKey);
      switch (outcome) {
        case ProfileSyncOutcome.unauthorized:
          return AdvisorChangeOutcome.unauthorized;
        case ProfileSyncOutcome.retryable:
          return AdvisorChangeOutcome.networkFailed;
        case ProfileSyncOutcome.ok:
          break;
      }
    }

    selectedAdvisor = advisorName;
    notifyListeners();
    await repository.save(_toRecord());
    return sync == null
        ? AdvisorChangeOutcome.localOnly
        : AdvisorChangeOutcome.synced;
  }

  void setFirstName(String name) {
    firstName = name;
    notifyListeners();
  }

  /// B10.1 — applique une édition de prénom / date de naissance faite depuis
  /// « Mon espace ». À n'appeler QU'APRÈS un PATCH backend réussi
  /// (`AuthController.syncProfileFields` -> `ProfileSyncOutcome.ok`) : local et
  /// serveur restent alignés. Persiste l'instantané via le repository.
  Future<void> applyIdentityEdit({
    String? firstName,
    DateTime? birthDate,
  }) async {
    if (firstName != null) this.firstName = firstName;
    if (birthDate != null) this.birthDate = birthDate;
    notifyListeners();
    await repository.save(_toRecord());
  }

  void setBirthDate(DateTime date) {
    birthDate = date;
    notifyListeners();
  }

  /// PROFIL SERVEUR (multi-appareil) — applique le profil réel récupéré via
  /// `GET /api/app/profile` (`AuthController.fetchServerProfile` ->
  /// `ProfileRestoreOutcome.ok`). Le serveur PRIME pour prénom / date de
  /// naissance / conseiller préféré dès qu'il renvoie une valeur.
  ///
  /// Tolérance profil PARTIEL : un paramètre `null` (le serveur n'a rien
  /// renvoyé pour ce champ) NE remplace PAS la valeur locale et n'invente
  /// aucune donnée. L'appelant a déjà résolu `advisorName` depuis le `guide`
  /// backend via l'unique mapping `advisorByGuideKey` — `null` si le guide est
  /// inconnu (aucun repli silencieux vers Séléna, pas de choix fabriqué).
  ///
  /// Ne touche à AUCUNE autre donnée (quota, Premium, temps de consultation,
  /// historique, Billing ont leurs propres sources serveur). Persiste
  /// l'instantané via le repository existant — un lancement hors ligne
  /// ultérieur réutilisera le dernier profil valide du même compte.
  Future<void> applyServerProfile({
    required String userId,
    String? firstName,
    DateTime? birthDate,
    String? advisorName,
  }) async {
    if (userId.isNotEmpty) this.userId = userId;
    if (firstName != null && firstName.isNotEmpty) this.firstName = firstName;
    if (birthDate != null) this.birthDate = birthDate;
    if (advisorName != null && advisorName.isNotEmpty) {
      selectedAdvisor = advisorName;
    }
    onboardingCompleted = true;
    notifyListeners();
    await repository.save(_toRecord());
  }

  void setPortraitData(String text) {
    portraitData = text;
    notifyListeners();
  }

  void setPortraitFeedback(String text) {
    portraitFeedback = text;
    notifyListeners();
  }

  /// Clôt l'onboarding local et persiste l'instantané via le repository.
  ///
  /// [userId] : identité réelle du compte (`accounts.user_id` renvoyé par
  /// `GET /api/account` après l'auth OTP). Si `null` (ex. réseau KO juste
  /// après la vérification du code), on retombe sur un identifiant temporaire
  /// local — la prochaine restauration de session récupérera le vrai.
  Future<void> completeOnboarding({String? userId}) async {
    this.userId = userId ?? this.userId ?? _generateTempUserId();
    onboardingCompleted = true;
    await repository.save(_toRecord());
    notifyListeners();
  }

  OnboardingRecord _toRecord() => OnboardingRecord(
    userId: userId,
    selectedAdvisor: selectedAdvisor,
    firstName: firstName,
    birthDate: birthDate,
    portraitData: portraitData,
    portraitFeedback: portraitFeedback,
    onboardingCompleted: onboardingCompleted,
  );

  /// Reset DEBUG uniquement — efface les données mock d'onboarding pour
  /// permettre de rejouer le parcours. Jamais exposé comme fonctionnalité
  /// utilisateur finale (voir le geste caché sur l'icône profil).
  Future<void> debugReset() => _wipeIdentity();

  /// RGPD — à appeler UNIQUEMENT après un succès serveur de suppression de
  /// compte ([AuthController.deleteAccount] -> [AccountDeletionOutcome.ok]).
  /// Efface l'identité EN MÉMOIRE (prénom, date de naissance, conseiller,
  /// portrait, userId) ET le snapshot persisté (`repository.clear()`), pour
  /// qu'aucune donnée de l'ancien utilisateur ne subsiste dans l'app.
  Future<void> clearForAccountDeletion() => _wipeIdentity();

  /// CHANGEMENT DE COMPTE — à appeler quand un AUTRE utilisateur se connecte
  /// sur cet appareil (`userId` authentifié ≠ `userId` local persisté). Évite
  /// d'afficher le prénom / conseiller / date de naissance de l'utilisateur
  /// précédent. Même effet que [clearForAccountDeletion] (l'app n'a pas encore
  /// de récupération de profil serveur au login).
  Future<void> forgetLocalIdentity() => _wipeIdentity();

  Future<void> _wipeIdentity() async {
    await repository.clear();
    userId = null;
    selectedAdvisor = null;
    firstName = null;
    birthDate = null;
    portraitData = null;
    portraitFeedback = null;
    onboardingCompleted = false;
    notifyListeners();
  }

  static String _generateTempUserId() {
    final random = Random();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'temp_$hex';
  }
}

/// Fournit [AuryelState] à tout l'arbre de widgets. `AuryelStateScope.of`
/// s'abonne aux changements (rebuild automatique sur `notifyListeners`).
class AuryelStateScope extends InheritedNotifier<AuryelState> {
  const AuryelStateScope({
    super.key,
    required AuryelState state,
    required super.child,
  }) : super(notifier: state);

  static AuryelState of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AuryelStateScope>();
    assert(
      scope != null,
      'AuryelStateScope introuvable dans l’arbre de widgets.',
    );
    return scope!.notifier!;
  }
}
