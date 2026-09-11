// Champs privés injectés par des paramètres nommés publics -> pas d'initializing
// formal possible sans exposer `_api` / `_token` comme noms de paramètres.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/wellbeing_api.dart';

/// État de « Mon parcours bien-être » pour l'écran dédié.
///
/// Le SERVEUR est l'unique autorité : [progress] est la réponse de
/// `GET /api/app/wellbeing/progress`. Rien n'est calculé ni persisté localement
/// SAUF l'accusé de réception de la confirmation de récompense
/// ([pendingRewardCycle]) — pur confort d'affichage « une seule fois », le
/// crédit lui-même est déjà fait côté serveur.
class WellbeingController extends ChangeNotifier {
  WellbeingController({
    required WellbeingApi api,
    required Future<String?> Function() tokenProvider,
    SharedPreferences? prefs,
  }) : _api = api,
       _token = tokenProvider,
       _injectedPrefs = prefs;

  final WellbeingApi _api;
  final Future<String?> Function() _token;
  final SharedPreferences? _injectedPrefs;

  static const String _ackKey = 'auryel.wellbeing.reward_ack.v1';

  WellbeingProgress? _progress;
  bool _loading = true; // vrai jusqu'au 1er chargement abouti
  bool _busy = false;
  Object? _error;
  int? _pendingRewardCycle;
  bool _disposed = false;
  Set<int> _acked = <int>{};

  WellbeingProgress? get progress => _progress;

  /// AUDIT ACCUEIL/PARCOURS — lecture UNIQUE de « la mission [id] est-elle
  /// faite aujourd'hui ? ». Accueil ET l'écran Parcours appellent ce même
  /// getter sur la MÊME instance partagée (voir [WellbeingScope]) : il ne
  /// peut plus exister deux vérités différentes pour une même mission.
  /// `false` tant que [progress] n'est pas encore chargé (jamais un faux
  /// "terminé" par défaut).
  bool isMissionDone(String id) =>
      _progress?.today.mission(id)?.completed ?? false;

  /// Chargement initial (aucune donnée encore).
  bool get loading => _loading && _progress == null;

  /// Un appel réseau (refresh ou enregistrement de mission) est en cours.
  bool get busy => _busy;

  /// Dernier échec de [refresh] / [recordMission]. Non bloquant : l'écran
  /// affiche un état d'erreur avec « Réessayer », la dernière progression
  /// connue reste visible.
  Object? get error => _error;

  /// Cycle dont la confirmation « Rayonnement atteint » n'a pas encore été vue.
  /// `null` = rien à afficher. L'écran appelle [acknowledgeReward] après.
  int? get pendingRewardCycle => _pendingRewardCycle;

  Future<SharedPreferences> get _prefs async =>
      _injectedPrefs ?? await SharedPreferences.getInstance();

  Future<void> _loadAcked() async {
    try {
      final p = await _prefs;
      _acked = (p.getStringList(_ackKey) ?? const <String>[])
          .map(int.tryParse)
          .whereType<int>()
          .toSet();
    } catch (_) {
      _acked = <int>{};
    }
  }

  void _recomputePendingReward({bool creditedNow = false}) {
    final prog = _progress;
    if (prog == null) {
      _pendingRewardCycle = null;
      return;
    }
    final earned = creditedNow || prog.rewardEarnedForCurrentCycle;
    _pendingRewardCycle = (earned && !_acked.contains(prog.cycleNumber))
        ? prog.cycleNumber
        : null;
  }

  /// `GET /api/app/wellbeing/progress`. Ne crédite jamais. Conserve la
  /// dernière progression connue en cas d'échec réseau / 5xx.
  Future<void> refresh() async {
    if (_busy || _disposed) return;
    if (_acked.isEmpty) await _loadAcked();

    final token = await _token();
    if (token == null || token.isEmpty || _disposed) return;

    _busy = true;
    _loading = true;
    _error = null;
    _notify();
    try {
      final prog = await _api.getProgress(token);
      if (_disposed) return;
      _progress = prog;
      _error = null;
      _recomputePendingReward();
    } on ApiUnauthorizedException catch (e) {
      _error = e; // l'écran laisse l'auth globale gérer un vrai 401 ailleurs
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

  /// `POST /api/app/wellbeing/mission { mission_id }`. La progression renvoyée
  /// remplace [progress]. Lève [WellbeingMissionActionMissing] (409) si
  /// l'action réelle d'une mission dérivée n'a pas eu lieu aujourd'hui — la
  /// progression n'est alors pas modifiée.
  Future<void> recordMission(String missionId) async {
    if (_busy || _disposed) return;
    if (_acked.isEmpty) await _loadAcked();

    final token = await _token();
    if (token == null || token.isEmpty || _disposed) return;

    _busy = true;
    _error = null;
    _notify();
    try {
      final prog = await _api.recordMission(
        bearer: token,
        missionId: missionId,
      );
      if (_disposed) return;
      _progress = prog;
      _error = null;
      _recomputePendingReward(creditedNow: prog.rewardCreditedNow);
    } on WellbeingMissionActionMissing {
      rethrow; // l'écran affiche « fais d'abord cette activité »
    } on ApiUnauthorizedException catch (e) {
      _error = e;
    } on ApiNetworkException catch (e) {
      _error = e;
    } on ApiException catch (e) {
      _error = e;
    } catch (e) {
      _error = e;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Marque la confirmation du cycle [cycle] comme vue (persistée). Idempotent.
  Future<void> acknowledgeReward(int cycle) async {
    _acked = {..._acked, cycle};
    if (_pendingRewardCycle == cycle) _pendingRewardCycle = null;
    _notify();
    try {
      final p = await _prefs;
      await p.setStringList(
        _ackKey,
        _acked.map((c) => c.toString()).toList(growable: false),
      );
    } catch (_) {
      /* la confirmation pourra réapparaître une fois — sans dommage */
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

/// AUDIT ACCUEIL/PARCOURS — fournit UNE instance PARTAGÉE de
/// [WellbeingController] à tout l'arbre (créée une fois dans `main()`, comme
/// [ConsultationScope] / [PurchaseScope]). C'est ce qui garantit qu'Accueil
/// et « Mon parcours bien-être » ne peuvent plus diverger : les deux lisent
/// et notifient la MÊME instance, jamais deux contrôleurs indépendants qui
/// interrogeraient chacun le serveur de leur côté.
class WellbeingScope extends InheritedNotifier<WellbeingController> {
  const WellbeingScope({
    super.key,
    required WellbeingController controller,
    required super.child,
  }) : super(notifier: controller);

  static WellbeingController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<WellbeingScope>();
    assert(scope != null, 'WellbeingScope introuvable dans l’arbre.');
    return scope!.notifier!;
  }

  static WellbeingController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WellbeingScope>()?.notifier;

  /// Sans dépendance de rebuild — l'appelant gère lui-même son abonnement
  /// (ex. via un `ListenableBuilder` explicite).
  static WellbeingController? maybeReadOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<WellbeingScope>()?.notifier;
}
