// Champs privés injectés par des paramètres nommés publics -> pas d'initializing
// formal possible sans exposer `_api` / `_token` comme noms de paramètres.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../api/rewards_api.dart';

/// Clé d'idempotence pour UNE tentative d'achat (ex. Consultation Express).
/// GÉNÉRÉE UNE FOIS par l'écran appelant puis réutilisée TELLE QUELLE tant
/// que la tentative n'a pas définitivement abouti (succès OU annulation
/// explicite) — un retry réseau / double tap avec la MÊME clé ne peut
/// jamais produire un 2e débit (idempotence garantie côté serveur).
String generateIdempotencyKey(String prefix) {
  final rand = Random.secure().nextInt(1 << 31);
  return '$prefix:${DateTime.now().toUtc().microsecondsSinceEpoch}:$rand';
}

/// État du wallet Étoiles Auryel pour tout l'arbre — le header Accueil
/// (« Mon compte » / « ⭐ solde ») et l'écran « Mes Étoiles » lisent et
/// notifient la MÊME instance (voir [RewardsScope]), exactement comme
/// [WellbeingController] : jamais deux copies du solde qui pourraient
/// diverger. Le SERVEUR reste l'unique autorité : [wallet] est la réponse
/// BRUTE de `GET /api/app/rewards/wallet`, rien n'est recalculé ni inventé
/// localement.
class RewardsController extends ChangeNotifier {
  RewardsController({
    required RewardsApi api,
    required Future<String?> Function() tokenProvider,
  }) : _api = api,
       _token = tokenProvider;

  final RewardsApi _api;
  final Future<String?> Function() _token;

  RewardWallet? _wallet;
  bool _loading = true; // vrai jusqu'au 1er chargement abouti
  bool _busy = false;
  Object? _error;
  bool _disposed = false;

  /// `null` tant que le 1er chargement n'a pas abouti — jamais un solde
  /// inventé à 0 par défaut (le header retombe alors sur un état neutre).
  RewardWallet? get wallet => _wallet;

  int get starsBalance => _wallet?.starsBalance ?? 0;
  List<RewardRule> get rules => _wallet?.rules ?? const <RewardRule>[];
  RewardStreak get streak => _wallet?.streak ?? RewardStreak.zero;
  List<RewardTransaction> get recentTransactions =>
      _wallet?.recentTransactions ?? const <RewardTransaction>[];
  List<ExpressProduct> get expressProducts =>
      _wallet?.expressProducts ?? const <ExpressProduct>[];

  /// Chargement initial (aucune donnée encore).
  bool get loading => _loading && _wallet == null;

  /// Un appel réseau (refresh ou claim) est en cours.
  bool get busy => _busy;

  /// Dernier échec de [refresh] / [claim]. Non bloquant : le dernier solde
  /// connu reste affiché.
  Object? get error => _error;

  /// `GET /api/app/rewards/wallet`. Ne crédite jamais. Conserve le dernier
  /// wallet connu en cas d'échec réseau / 5xx — ne jamais afficher 0 par
  /// erreur après une simple coupure réseau.
  Future<void> refresh() async {
    if (_busy || _disposed) return;
    final token = await _token();
    if (token == null || token.isEmpty || _disposed) return;

    _busy = true;
    _loading = true;
    _error = null;
    _notify();
    try {
      final w = await _api.getWallet(token);
      if (_disposed) return;
      _wallet = w;
      _error = null;
    } on ApiUnauthorizedException catch (e) {
      _error = e; // l'auth globale gère un vrai 401 ailleurs
    } on ApiNetworkException catch (e) {
      _error = e;
    } on ApiException catch (e) {
      _error = e;
    } catch (e) {
      _error = e;
    } finally {
      _busy = false;
      _loading = false;
      _notify();
    }
  }

  /// `POST /api/app/rewards/claim { action_key }` — UNIQUEMENT pour les
  /// actions sans preuve serveur indépendante (aujourd'hui : `wake_completed`
  /// depuis l'écran de réveil). Rafraîchit [wallet] depuis le serveur après
  /// coup (jamais un solde local incrémenté à la main) : le retour donne
  /// juste de quoi afficher un feedback bref (« +5 ⭐ ») pendant la journée.
  /// Retourne `null` sur échec réseau (absorbé, jamais bloquant pour
  /// l'écran appelant).
  Future<RewardClaimResult?> claim(String actionKey) async {
    if (_disposed) return null;
    final token = await _token();
    if (token == null || token.isEmpty || _disposed) return null;

    try {
      final result = await _api.claimAction(
        bearer: token,
        actionKey: actionKey,
      );
      if (result.awarded) {
        // Solde optimiste immédiat (le header réagit sans attendre un 2e
        // aller-retour), CONFIRMÉ juste après par [refresh] — jamais la
        // seule source affichée durablement.
        final current = _wallet;
        if (current != null) {
          _wallet = RewardWallet(
            starsBalance: result.newBalance,
            rules: current.rules,
            streak: current.streak,
            recentTransactions: current.recentTransactions,
            expressProducts: current.expressProducts,
          );
          _notify();
        }
      }
      unawaited(refresh());
      return result;
    } catch (_) {
      return null;
    }
  }

  /// GROS CHANTIER AURYEL (Prompt 3/5) — CONSULTATION EXPRESS : débloque du
  /// temps de consultation contre des Étoiles. `idempotencyKey` DOIT être
  /// STABLE pour une même tentative d'achat — c'est L'APPELANT (l'écran) qui
  /// la génère UNE fois et la réutilise telle quelle sur un retry (double
  /// tap, timeout, réponse perdue) : voir [generateIdempotencyKey].
  /// `success=false` (ex. solde insuffisant) n'est PAS une erreur — le solde
  /// n'est modifié QUE si `success=true`. Retourne `null` sur échec réseau
  /// (absorbé, jamais bloquant pour l'écran appelant).
  Future<ExpressConsultationResult?> purchaseExpressConsultation({
    required String productKey,
    required String idempotencyKey,
  }) async {
    if (_disposed) return null;
    final token = await _token();
    if (token == null || token.isEmpty || _disposed) return null;

    try {
      final result = await _api.purchaseExpressConsultation(
        bearer: token,
        productKey: productKey,
        idempotencyKey: idempotencyKey,
      );
      if (result.success) {
        // Solde optimiste immédiat, CONFIRMÉ juste après par [refresh].
        final current = _wallet;
        if (current != null) {
          _wallet = RewardWallet(
            starsBalance: result.starsBalance,
            rules: current.rules,
            streak: current.streak,
            recentTransactions: current.recentTransactions,
            expressProducts: current.expressProducts,
          );
          _notify();
        }
      }
      unawaited(refresh());
      return result;
    } catch (_) {
      return null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Fournit UNE instance PARTAGÉE de [RewardsController] à tout l'arbre
/// (créée une fois dans `main()`, comme [WellbeingScope] / [ConsultationScope]).
class RewardsScope extends InheritedNotifier<RewardsController> {
  const RewardsScope({
    super.key,
    required RewardsController controller,
    required super.child,
  }) : super(notifier: controller);

  static RewardsController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RewardsScope>();
    assert(scope != null, 'RewardsScope introuvable dans l’arbre.');
    return scope!.notifier!;
  }

  static RewardsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RewardsScope>()?.notifier;

  /// Sans dépendance de rebuild — l'appelant gère lui-même son abonnement.
  static RewardsController? maybeReadOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<RewardsScope>()?.notifier;
}
