import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
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

/// État d'authentification partagé. Séparé de `AuryelState` (onboarding métier)
/// pour ne pas mélanger les responsabilités.
class AuthController extends ChangeNotifier {
  AuthController({required AuthRepository repository}) : _repo = repository;

  final AuthRepository _repo;

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
}
