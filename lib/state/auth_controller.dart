import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../api/consultation_api.dart';
import '../api/profile_api.dart';
import '../api/tirage_api.dart';
import '../data/account.dart';
import '../data/auth_repository.dart';

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
  })  : _repo = repository,
        _profileApi = profileApi,
        _consultationApi = consultationApi,
        _tirageApi = tirageApi;

  final AuthRepository _repo;
  final ProfileApi _profileApi;
  final ConsultationApi _consultationApi;
  final TirageApi _tirageApi;

  /// Exposé pour les écrans qui appellent le backend consultation (F3+).
  ConsultationApi get consultationApi => _consultationApi;

  /// Exposé pour l'écran Tirage (T3) et la Bibliothèque — save + historique.
  TirageApi get tirageApi => _tirageApi;

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

  /// Étape 1 du login. Relaie les erreurs à l'écran appelant.
  Future<void> requestCode(String email) => _repo.requestCode(email);

  /// Étape 2 : vérifie le code, stocke le jeton, confirme via `GET /api/account`.
  /// - code invalide/expiré -> lève [ApiException] (aucun jeton écrit).
  /// - jeton OK mais réseau KO sur /account -> session considérée ouverte
  ///   (mode dégradé), pas d'exception.
  Future<void> verifyCode(String email, String code) async {
    await _repo.verifyCodeAndStore(email, code);
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

  Future<void> logout() async {
    await _repo.logout();
    _set(AuthStatus.signedOut, null);
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
