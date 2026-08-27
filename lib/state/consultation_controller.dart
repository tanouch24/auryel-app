// Champs privés injectés par des paramètres nommés publics -> pas d'initializing
// formal possible sans exposer `_api` / `_auth` comme noms de paramètres.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../api/consultation_api.dart';
import '../data/consultation.dart';
import 'auth_controller.dart';

/// État global d'une consultation active, partagé dans toute l'app (F4).
///
/// Règles :
///  - Le serveur est SEULE source de vérité. `expires_at` renvoyé par le
///    backend fait foi ; on ne décrémente JAMAIS `seconds_remaining` localement.
///  - Le temps restant affiché est dérivé de `active.expiresAt - now (UTC)`.
///  - Un [Timer.periodic] d'1 s sert UNIQUEMENT à `notifyListeners()` pour
///    rafraîchir l'affichage — il ne modifie aucune donnée.
///  - Session expirée localement (`expiresAt` dépassé) => l'UI la considère
///    terminée, n'ouvre jamais de nouvelle session toute seule ; le prochain
///    `refresh()` serveur confirmera.
class ConsultationController extends ChangeNotifier {
  ConsultationController({
    required ConsultationApi api,
    required AuthController auth,
  })  : _api = api,
        _auth = auth;

  final ConsultationApi _api;
  final AuthController _auth;

  ConsultationDto? _active;
  QuotaDto? _quota;
  bool _refreshing = false;
  Object? _refreshError;
  Timer? _ticker;
  bool _disposed = false;

  ConsultationDto? get active => _active;
  QuotaDto? get quota => _quota;
  bool get refreshing => _refreshing;
  Object? get refreshError => _refreshError;

  /// `true` dès que `expiresAt` est dépassé (comparaison en UTC).
  bool get isExpired {
    final exp = _active?.expiresAt;
    if (exp == null) return false;
    return !exp.isAfter(DateTime.now().toUtc());
  }

  /// Session réellement exploitable : présente ET pas encore expirée.
  bool get hasActiveSession => _active != null && !isExpired;

  /// Temps restant dérivé du serveur, jamais négatif. `Duration.zero` si
  /// expiré ou si le backend n'a pas fourni `expires_at`.
  Duration get remaining {
    final exp = _active?.expiresAt;
    if (exp == null) return Duration.zero;
    final r = exp.difference(DateTime.now().toUtc());
    return r.isNegative ? Duration.zero : r;
  }

  /// « 1h40 » — utilisé par l'Accueil (« Reprendre ma consultation · 1h40
  /// restante ») et le bloc consultation.
  static String formatRemaining(Duration d) {
    final total = d.isNegative ? Duration.zero : d;
    final h = total.inHours;
    final m = total.inMinutes.remainder(60);
    return '${h}h${m.toString().padLeft(2, '0')}';
  }

  /// Resynchronisation depuis `GET /api/consultation/state`.
  ///  - pas de jeton -> aucun appel.
  ///  - 200 -> `active` + `quota` remplacés par les valeurs serveur
  ///    (`consultation: null` => plus de session active).
  ///  - 401 -> `active` vidé + [AuthController.invalidateSession].
  ///  - réseau / 5xx -> on CONSERVE `active` + `quota` connus, on note
  ///    `refreshError`, on ne purge rien.
  Future<void> refresh() async {
    if (_refreshing || _disposed) return;

    final token = await _auth.currentToken();
    if (token == null || token.isEmpty || _disposed) return;

    _refreshing = true;
    _refreshError = null;
    notifyListeners();

    try {
      final res = await _api.getState(bearer: token);
      _active = res.consultation;
      _quota = res.quota;
      _refreshError = null;
      _syncTimer();
    } on ApiUnauthorizedException {
      _active = null;
      _syncTimer();
      await _auth.invalidateSession();
    } on ApiNetworkException catch (e) {
      _refreshError = e;
    } on ApiException catch (e) {
      _refreshError = e;
    } catch (e) {
      _refreshError = e;
    } finally {
      _refreshing = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Injection immédiate de l'état après un `POST /api/consultation/message`
  /// réussi (le ChatScreen a déjà la réponse en main : pas de re-GET).
  void updateFromMessageResponse(ConsultationMessageResponse res) {
    if (res.consultation != null) {
      _active = res.consultation;
    }
    _quota = res.quota;
    _refreshError = null;
    _syncTimer();
    notifyListeners();
  }

  /// Resynchro du quota après un 402 `no_credit` : on met à jour `quota` si le
  /// corps en portait un, sans jamais fabriquer de session active.
  void applyNoCredit(QuotaDto? quota) {
    if (quota == null) return;
    _quota = quota;
    notifyListeners();
  }

  void _syncTimer() {
    _ticker?.cancel();
    _ticker = null;
    if (_disposed) return;
    if (_active != null && !isExpired) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_disposed) {
          _ticker?.cancel();
          _ticker = null;
          return;
        }
        notifyListeners();
        if (_active == null || isExpired) {
          _ticker?.cancel();
          _ticker = null;
        }
      });
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }
}

/// Fournit [ConsultationController] à l'arbre (rebuild sur `notifyListeners`).
class ConsultationScope extends InheritedNotifier<ConsultationController> {
  const ConsultationScope({
    super.key,
    required ConsultationController controller,
    required super.child,
  }) : super(notifier: controller);

  static ConsultationController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ConsultationScope>();
    assert(scope != null, 'ConsultationScope introuvable dans l’arbre.');
    return scope!.notifier!;
  }

  static ConsultationController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConsultationScope>()?.notifier;

  /// Récupère le contrôleur SANS créer de dépendance de rebuild (l'appelant
  /// gère lui-même son abonnement, ex. via un [ListenableBuilder]). Évite de
  /// reconstruire tout l'écran hôte à chaque tick d'1 s.
  static ConsultationController readOf(BuildContext context) {
    final controller = maybeReadOf(context);
    assert(controller != null, 'ConsultationScope introuvable dans l’arbre.');
    return controller!;
  }

  /// Variante nullable de [readOf] : renvoie `null` si aucun scope n'est
  /// présent (utile pour les écrans montés isolément dans les tests).
  static ConsultationController? maybeReadOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ConsultationScope>()?.notifier;
}
