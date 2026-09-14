import 'package:flutter/widgets.dart';

import '../api/account_api.dart';
import '../api/ai_report_api.dart';
import '../api/api_client.dart';
import '../api/consultation_api.dart';
import '../api/memory_api.dart';
import '../api/mini_game_api.dart';
import '../api/support_api.dart';
import '../api/profile_api.dart';
import '../api/rewards_api.dart';
import '../api/tirage_api.dart';
import '../api/wellbeing_api.dart';
import '../data/account.dart';
import '../data/app_profile.dart';
import '../data/auth_repository.dart';
import '../data/installation_id_store.dart';
import '../data/local_user_data.dart';

enum AuthStatus {
  /// Restauration pas encore tentée.
  unknown,

  /// Pas de session (jamais connecté, ou déconnecté).
  signedOut,

  /// Session valide (jeton accepté par le backend).
  signedIn,

  /// Le jeton stocké a été rejeté (401) et purgé — il faut se reconnecter.
  sessionExpired,

  /// Session probablement valide mais backend injoignable au démarrage
  /// (jeton conservé, mode dégradé).
  networkError,
}

/// Issue d'une tentative de suppression de compte (B10).
enum AccountDeletionOutcome {
  /// Serveur a confirmé : compte supprimé, données locales purgées, `signedOut`.
  ok,

  /// Endpoint non câblé (aucun [AccountApi]) — rien tenté, rien touché.
  unavailable,

  /// 401 pendant le DELETE : jeton mort, session purgée + `sessionExpired`.
  unauthorized,

  /// Réseau / 5xx : RIEN touché, session conservée, réessai possible.
  retryable,
}

/// Issue d'une récupération du profil serveur réel (`GET /api/app/profile`)
/// pour un compte déjà authentifié — restauration multi-appareil / changement
/// de compte / profil local perdu.
enum ProfileRestoreOutcome {
  /// Profil serveur récupéré. Peut être PARTIEL (prénom / date / guide vides) —
  /// l'appelant ne remplace jamais une valeur locale par un vide serveur.
  ok,

  /// 401 pendant le GET : jeton mort — session purgée + `sessionExpired`
  /// (politique 401 UNIQUE, identique au reste de l'auth). L'appelant renvoie
  /// au login.
  unauthorized,

  /// Réseau KO / 5xx / 404 / jeton absent : session CONSERVÉE, l'appelant
  /// garde le profil local existant du même compte (ou un profil vide honnête).
  retryable,
}

/// Retour de [AuthController.fetchServerProfile] : l'issue + le profil (non
/// `null` uniquement sur [ProfileRestoreOutcome.ok]).
typedef ProfileRestoreResult = ({
  ProfileRestoreOutcome outcome,
  AppProfile? profile,
});

/// Résultat de la synchro du profil onboarding vers le backend (B4.3).
enum ProfileSyncOutcome {
  /// PATCH accepté — on peut clôturer l'onboarding et entrer dans l'app.
  ok,

  /// 401 pendant le PATCH : session invalidée (jeton purgé) — retour au login.
  unauthorized,

  /// Réseau KO / 5xx : jeton CONSERVÉ, l'utilisateur peut réessayer sans
  /// redemander de code.
  retryable,
}

/// État d'authentification partagé. Séparé de `AuryelState` (onboarding métier)
/// pour ne pas mélanger les responsabilités.
class AuthController extends ChangeNotifier {
  // Champs privés -> pas d'« initializing formal » possible.
  // ignore_for_file: prefer_initializing_formals
  AuthController({
    required AuthRepository repository,
    required ProfileApi profileApi,
    required ConsultationApi consultationApi,
    required TirageApi tirageApi,
    AiReportApi? aiReportApi,
    AccountApi? accountApi,
    RewardsApi? rewardsApi,
    WellbeingApi? wellbeingApi,
    MemoryApi? memoryApi,
    MiniGameApi? miniGameApi,
    SupportApi? supportApi,
    LocalUserData? localUserData,
    InstallationIdStore? installationIdStore,
    Future<void> Function()? pushUnregister,
  }) : _repo = repository,
       _pushUnregister = pushUnregister,
       _profileApi = profileApi,
       _consultationApi = consultationApi,
       _tirageApi = tirageApi,
       _aiReportApi = aiReportApi,
       _accountApi = accountApi,
       _rewardsApi = rewardsApi,
       _wellbeingApi = wellbeingApi,
       _memoryApi = memoryApi,
       _miniGameApi = miniGameApi,
       _supportApi = supportApi,
       _localUserData = localUserData ?? LocalUserData(),
       _installationIdStore = installationIdStore;

  final AuthRepository _repo;
  final ProfileApi _profileApi;
  final ConsultationApi _consultationApi;
  final TirageApi _tirageApi;
  final AiReportApi? _aiReportApi;
  final AccountApi? _accountApi;
  final RewardsApi? _rewardsApi;
  final WellbeingApi? _wellbeingApi;
  final MemoryApi? _memoryApi;
  final MiniGameApi? _miniGameApi;
  final SupportApi? _supportApi;
  final LocalUserData _localUserData;
  final InstallationIdStore? _installationIdStore;

  /// Désenregistrement du jeton push de CET appareil, exécuté AVANT de perdre
  /// le Bearer (logout / suppression de compte). Best effort : ne bloque
  /// jamais, n'échoue jamais l'opération. `null` dans les tests hérités.
  ///
  /// Peut être fourni au constructeur ou rattaché après coup (le
  /// `NotificationCoordinator` est construit après l'`AuthController`).
  Future<void> Function()? _pushUnregister;

  // ignore: use_setters_to_change_properties
  void attachPushUnregister(Future<void> Function() hook) {
    _pushUnregister = hook;
  }

  Future<void> _runPushUnregister() async {
    final hook = _pushUnregister;
    if (hook == null) return;
    try {
      await hook();
    } catch (_) {
      /* le push ne bloque jamais un logout / une suppression */
    }
  }

  /// Exposé pour les écrans qui appellent le backend consultation (F3+).
  ConsultationApi get consultationApi => _consultationApi;

  /// Exposé pour l'écran Tirage (T3) et la Bibliothèque — save + historique.
  TirageApi get tirageApi => _tirageApi;

  /// Signalement d'une réponse IA (ChatScreen). `null` tant qu'aucune instance
  /// n'est câblée (tests hérités) — l'appelant affiche alors l'état d'erreur,
  /// jamais un faux succès.
  AiReportApi? get aiReportApi => _aiReportApi;

  /// Récompenses côté app (progression partage 30 jours). `null` si non câblé.
  RewardsApi? get rewardsApi => _rewardsApi;

  /// Parcours bien-être (missions quotidiennes + récompense par cycle de 30
  /// journées). `null` si non câblé (tests hérités).
  WellbeingApi? get wellbeingApi => _wellbeingApi;

  /// Jeu Auryel (Memory) + récompenses de temps de consultation. `null` si non
  /// câblé (tests hérités) — le jeu reste jouable, sans récompense.
  MemoryApi? get memoryApi => _memoryApi;

  /// Suite intuitive / Carte cachée (Prompt 3/5) — session serveur générique,
  /// même règle de récompense partagée que Memory. `null` si non câblé (tests
  /// hérités) — le jeu reste jouable, sans récompense.
  MiniGameApi? get miniGameApi => _miniGameApi;

  /// « Signaler un problème » (POST /api/app/support). `null` si non câblé.
  SupportApi? get supportApi => _supportApi;

  /// `true` si la suppression réelle de compte est disponible (endpoint câblé).
  bool get accountDeletionAvailable => _accountApi != null;

  /// SEAM anti-abus « heure gratuite » — identifiant d'INSTALLATION (pas de
  /// compte), conservé au logout / changement de compte / suppression.
  ///
  /// AUJOURD'HUI : rien n'est envoyé au backend. `installation_id` N'EST PAS
  /// ajouté aux payloads (`register` / `login` / `profile` inchangés) tant que
  /// le contrat backend ne l'accepte pas officiellement. Ce getter permet à un
  /// lot ultérieur de faire `await auth.installationId()` et de transmettre le
  /// champ exact — cf. `docs/installation_id_anti_abuse.md`.
  Future<String?> installationId() async => _installationIdStore?.getOrCreate();

  /// Jeton Bearer courant (ou null). Passthrough vers le stockage sécurisé.
  Future<String?> currentToken() => _repo.currentToken();

  /// Invalidation de session sur 401 rencontré hors login (ex. chat) :
  /// purge locale + statut sessionExpired. L'appelant renvoie au login.
  Future<void> invalidateSession() async {
    await _repo.clearSession();
    _set(AuthStatus.sessionExpired, null);
  }

  AuthStatus _status = AuthStatus.unknown;
  Account? _account;

  AuthStatus get status => _status;
  Account? get account => _account;
  bool get isSignedIn =>
      _status == AuthStatus.signedIn || _status == AuthStatus.networkError;

  /// Au lancement de l'app.
  Future<void> restore() async {
    final result = await _repo.restoreSession();
    switch (result.outcome) {
      case RestoreOutcome.noToken:
        _set(AuthStatus.signedOut, null);
      case RestoreOutcome.valid:
        _set(AuthStatus.signedIn, result.account);
      case RestoreOutcome.expired:
        _set(AuthStatus.sessionExpired, null);
      case RestoreOutcome.networkError:
        _set(AuthStatus.networkError, null);
    }
  }

  /// AUTH V2 — crée le compte (email + mot de passe), stocke le jeton, confirme
  /// via `GET /api/account`. Mêmes règles post-jeton que [verifyCode] :
  /// - erreurs métier (400/409/503) -> lèvent [ApiException] (aucun jeton écrit) ;
  /// - jeton OK mais réseau KO sur /account -> session ouverte en mode dégradé.
  Future<void> registerWithPassword(String email, String password) =>
      _authWithToken(() => _repo.registerWithPasswordAndStore(email, password));

  /// AUTH V2 — connexion (email + mot de passe). Voir [registerWithPassword].
  Future<void> loginWithPassword(String email, String password) =>
      _authWithToken(() => _repo.loginWithPasswordAndStore(email, password));

  /// Socle commun register/login/verify-code : obtient+stocke un jeton via
  /// [obtainToken], puis résout le compte. Ne touche jamais au mot de passe.
  Future<void> _authWithToken(Future<String> Function() obtainToken) async {
    await obtainToken();
    try {
      final account = await _repo.fetchAccount();
      _set(AuthStatus.signedIn, account);
    } on ApiUnauthorizedException {
      _set(AuthStatus.sessionExpired, null);
      rethrow;
    } on ApiNetworkException {
      _set(AuthStatus.networkError, null);
    }
  }

  /// LEGACY (OTP) — étape 1. Hors parcours actif (conservé pour le futur
  /// « définir un mot de passe » d'un ancien compte).
  Future<void> requestCode(String email) => _repo.requestCode(email);

  /// LEGACY (OTP) — étape 2 : vérifie le code, stocke le jeton, confirme via
  /// `GET /api/account`. Hors parcours actif.
  Future<void> verifyCode(String email, String code) =>
      _authWithToken(() => _repo.verifyCodeAndStore(email, code));

  /// B4.3 — pousse le profil onboarding vers `PATCH /api/app/profile` avec le
  /// jeton courant. Applique les mêmes règles 401 que le reste de l'auth
  /// (purge + sessionExpired). Ne clôt PAS l'onboarding : c'est l'appelant qui
  /// le fait, uniquement sur [ProfileSyncOutcome.ok].
  Future<ProfileSyncOutcome> syncProfile({
    required String guide,
    required String prenom,
    required String dateNaissance,
  }) async {
    final token = await _repo.currentToken();
    if (token == null || token.isEmpty) {
      _set(AuthStatus.signedOut, null);
      return ProfileSyncOutcome.unauthorized;
    }
    try {
      await _profileApi.patchProfile(
        token,
        guide: guide,
        prenom: prenom,
        dateNaissance: dateNaissance,
      );
      return ProfileSyncOutcome.ok;
    } on ApiUnauthorizedException {
      await _repo.clearSession();
      _set(AuthStatus.sessionExpired, null);
      return ProfileSyncOutcome.unauthorized;
    } on ApiNetworkException {
      return ProfileSyncOutcome.retryable;
    } on ApiException {
      return ProfileSyncOutcome.retryable;
    }
  }

  /// B10.1 — édition d'un ou plusieurs champs de profil depuis « Mon espace »
  /// (`prenom`, `date_naissance`). PATCH PARTIEL : seuls les champs non nuls
  /// sont transmis. Mêmes règles 401 que le reste de l'auth (purge +
  /// sessionExpired). N'ouvre aucune consultation, ne consomme aucun crédit.
  ///
  /// L'appelant ne met à jour l'état local QU'APRÈS un [ProfileSyncOutcome.ok]
  /// — aucune divergence local/serveur, aucun faux succès.
  Future<ProfileSyncOutcome> syncProfileFields({
    String? prenom,
    String? dateNaissance,
  }) async {
    if (prenom == null && dateNaissance == null) return ProfileSyncOutcome.ok;
    final token = await _repo.currentToken();
    if (token == null || token.isEmpty) {
      _set(AuthStatus.signedOut, null);
      return ProfileSyncOutcome.unauthorized;
    }
    try {
      await _profileApi.patchProfile(
        token,
        prenom: prenom,
        dateNaissance: dateNaissance,
      );
      return ProfileSyncOutcome.ok;
    } on ApiUnauthorizedException {
      await _repo.clearSession();
      _set(AuthStatus.sessionExpired, null);
      return ProfileSyncOutcome.unauthorized;
    } on ApiNetworkException {
      return ProfileSyncOutcome.retryable;
    } on ApiException {
      return ProfileSyncOutcome.retryable;
    }
  }

  /// UX-B §6/§8 — change UNIQUEMENT le conseiller préféré côté backend
  /// (`PATCH /api/app/profile { guide }`). Aucun autre champ n'est renvoyé :
  /// pas besoin de re-transmettre prénom / date de naissance. Ne consomme
  /// aucun crédit, ne crée aucune consultation (endpoint profil pur).
  ///
  /// Mêmes règles 401 que le reste de l'auth (purge + sessionExpired).
  Future<ProfileSyncOutcome> syncGuide({required String guide}) async {
    final token = await _repo.currentToken();
    if (token == null || token.isEmpty) {
      _set(AuthStatus.signedOut, null);
      return ProfileSyncOutcome.unauthorized;
    }
    try {
      await _profileApi.patchProfile(token, guide: guide);
      return ProfileSyncOutcome.ok;
    } on ApiUnauthorizedException {
      await _repo.clearSession();
      _set(AuthStatus.sessionExpired, null);
      return ProfileSyncOutcome.unauthorized;
    } on ApiNetworkException {
      return ProfileSyncOutcome.retryable;
    } on ApiException {
      return ProfileSyncOutcome.retryable;
    }
  }

  /// PROFIL MULTI-APPAREIL — récupère le profil serveur réel (prénom, date de
  /// naissance, conseiller préféré) d'un compte connecté, via
  /// `GET /api/app/profile` et le jeton courant.
  ///
  /// À appeler APRÈS un login réussi, et au démarrage quand le profil local est
  /// absent / incomplet / rattaché à un autre `userId`. Aucune consultation
  /// ouverte, aucun crédit consommé (endpoint profil pur).
  ///
  /// - 401  -> purge + `sessionExpired` (politique 401 unique) ->
  ///   [ProfileRestoreOutcome.unauthorized].
  /// - réseau / 5xx / 404 / jeton absent -> session CONSERVÉE ->
  ///   [ProfileRestoreOutcome.retryable] (l'appelant garde le profil local).
  /// - succès -> [ProfileRestoreOutcome.ok] + [AppProfile] (éventuellement
  ///   partiel).
  ///
  /// Ne touche PAS au quota / Premium / temps de consultation / historique /
  /// Billing : ces données ont leurs propres sources serveur.
  Future<ProfileRestoreResult> fetchServerProfile() async {
    final token = await _repo.currentToken();
    if (token == null || token.isEmpty) {
      return (outcome: ProfileRestoreOutcome.retryable, profile: null);
    }
    try {
      final profile = await _profileApi.getProfile(token);
      return (outcome: ProfileRestoreOutcome.ok, profile: profile);
    } on ApiUnauthorizedException {
      await _repo.clearSession();
      _set(AuthStatus.sessionExpired, null);
      return (outcome: ProfileRestoreOutcome.unauthorized, profile: null);
    } on ApiNetworkException {
      return (outcome: ProfileRestoreOutcome.retryable, profile: null);
    } on ApiException {
      return (outcome: ProfileRestoreOutcome.retryable, profile: null);
    }
  }

  Future<void> logout() async {
    // AVANT de perdre le Bearer : désenregistrer le jeton push de cet appareil
    // (best effort — ne désactive JAMAIS les autres appareils du compte).
    await _runPushUnregister();
    await _repo.logout();
    _set(AuthStatus.signedOut, null);
  }

  /// B10 — suppression RÉELLE du compte.
  ///
  /// Ordre STRICT (aucun faux succès, aucune suppression locale prématurée) :
  ///  1. jeton courant requis ;
  ///  2. `DELETE /api/app/account` authentifié ;
  ///  3. SUR SUCCÈS SERVEUR seulement -> purge des données locales personnelles
  ///     ([LocalUserData]) + purge du jeton + état `signedOut` ;
  ///  4. SUR ÉCHEC (réseau / 5xx) -> RIEN n'est touché, session conservée,
  ///     l'appelant peut réessayer ;
  ///  5. SUR 401 -> le jeton est de toute façon mort : purge locale + état
  ///     `sessionExpired` (retour login), mais on NE prétend PAS avoir supprimé.
  Future<AccountDeletionOutcome> deleteAccount() async {
    final api = _accountApi;
    if (api == null) return AccountDeletionOutcome.unavailable;
    final token = await _repo.currentToken();
    if (token == null || token.isEmpty) {
      _set(AuthStatus.signedOut, null);
      return AccountDeletionOutcome.unauthorized;
    }
    try {
      await api.deleteAccount(token);
    } on ApiUnauthorizedException {
      await _repo.clearSession();
      _set(AuthStatus.sessionExpired, null);
      return AccountDeletionOutcome.unauthorized;
    } on ApiNetworkException {
      return AccountDeletionOutcome.retryable; // session CONSERVÉE
    } on ApiException {
      return AccountDeletionOutcome.retryable; // session CONSERVÉE
    }
    // Succès serveur confirmé -> on nettoie, dans cet ordre.
    // Désenregistrement push best-effort AVANT la purge du jeton (le serveur
    // purge de toute façon push_devices dans la transaction de suppression).
    await _runPushUnregister();
    await _localUserData.clearPersonal();
    await _repo.clearSession();
    _set(AuthStatus.signedOut, null);
    return AccountDeletionOutcome.ok;
  }

  void _set(AuthStatus status, Account? account) {
    _status = status;
    _account = account;
    notifyListeners();
  }
}

/// Fournit [AuthController] à l'arbre de widgets (rebuild sur `notifyListeners`).
class AuthScope extends InheritedNotifier<AuthController> {
  const AuthScope({
    super.key,
    required AuthController controller,
    required super.child,
  }) : super(notifier: controller);

  static AuthController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'AuthScope introuvable dans l’arbre de widgets.');
    return scope!.notifier!;
  }

  /// Variante nullable : `null` si aucun [AuthScope] n'est présent (utile pour
  /// les écrans montés isolément dans des tests sans pile d'auth complète).
  static AuthController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthScope>()?.notifier;
}
