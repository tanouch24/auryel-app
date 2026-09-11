// Champs privés injectés par des paramètres nommés publics -> pas d'initializing
// formal possible sans exposer `_api` / `_auth` comme noms de paramètres.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../analytics/meta_events.dart';
import '../api/api_client.dart';
import '../api/consultation_api.dart';
import '../data/consultation.dart';
import 'auth_controller.dart';

/// État global d'une consultation, partagé dans toute l'app (F4 / TIMER-D.1).
///
/// Règles :
///  - Le serveur est SEULE source de vérité. On ne décrémente JAMAIS le temps
///    localement.
///  - SOURCE DE VÉRITÉ DU TEMPS : le bloc `time` (`ConsultationTimeState`) —
///    `time.totalRemainingSeconds` + les 3 buckets. On ne dérive PLUS le temps
///    de `expiresAt - now` ; `expiresAt` n'est qu'une valeur de compat backend.
///  - SOURCE DE VÉRITÉ FENÊTRE ACTIVE : `time.windowActive` /
///    `time.windowExpiresAt` (fenêtre de facturation de 5 min). Elle NE
///    détermine PAS si la consultation est « finie » : hors fenêtre,
///    l'historique reste visible et l'utilisateur peut reprendre.
///  - Fallback backend ANCIEN (bloc `time` absent, avant déploiement
///    coordonné) : on retombe sur `consultation.secondsRemaining` (que le
///    nouveau backend remplit déjà avec le total). Isolé dans [_walletSeconds].
///  - Un [Timer.periodic] d'1 s sert UNIQUEMENT à `notifyListeners()` pendant
///    une fenêtre active — il ne modifie aucune donnée.
class ConsultationController extends ChangeNotifier {
  ConsultationController({
    required ConsultationApi api,
    required AuthController auth,
    MetaEvents metaEvents = const NoopMetaEvents(),
  }) : _api = api,
       _auth = auth,
       _meta = metaEvents;

  final ConsultationApi _api;
  final AuthController _auth;
  final MetaEvents _meta;

  ConsultationDto? _active;
  QuotaDto? _quota;
  ConsultationTimeState? _time;
  bool _refreshing = false;
  Object? _refreshError;
  Timer? _ticker;
  bool _disposed = false;

  // J6 — LISTE des fils de discussion (un par conseiller). Séparée du snapshot
  // `_active` (compat `/state`). C'est cette liste que consommera la nouvelle
  // UI « Consultations en cours » (J6-F2). Jamais persistée : l'utilisateur
  // revient toujours sur la liste et choisit lui-même son fil.
  List<ConsultationSummaryDto> _consultations = const [];
  bool _consultationsLoading = false;
  Object? _consultationsError;

  ConsultationDto? get active => _active;
  QuotaDto? get quota => _quota;

  /// J6 — tous les fils connus, ordre backend (« le plus récemment actif
  /// d'abord »). Copie non modifiable.
  List<ConsultationSummaryDto> get consultations =>
      List.unmodifiable(_consultations);
  bool get hasConsultations => _consultations.isNotEmpty;
  bool get consultationsLoading => _consultationsLoading;

  /// Dernier échec de [refreshConsultations] (réseau / 5xx / 401). N'entraîne
  /// JAMAIS de déconnexion et NE vide PAS la liste connue.
  Object? get consultationsError => _consultationsError;

  /// SOURCE DE VÉRITÉ DU TEMPS. `null` tant que le backend distant est ancien
  /// (aucun bloc `time` reçu) — les getters ci-dessous appliquent alors le
  /// fallback [_walletSeconds].
  ConsultationTimeState? get time => _time;

  bool get refreshing => _refreshing;
  Object? get refreshError => _refreshError;

  /// Secondes de temps disponible. Priorité au bloc `time` du serveur ;
  /// fallback backend ancien = `consultation.secondsRemaining` (le nouveau
  /// backend y met déjà le total). Jamais négatif.
  int get _walletSeconds {
    final t = _time?.totalRemainingSeconds;
    if (t != null) return t < 0 ? 0 : t;
    final s = _active?.secondsRemaining ?? 0;
    return s < 0 ? 0 : s;
  }

  /// `true` quand le portefeuille de temps est vide alors qu'une consultation
  /// existe. N'a plus rien à voir avec `expiresAt` : c'est « plus de temps »,
  /// pas « 2 h écoulées ».
  bool get isExpired => _active != null && _walletSeconds <= 0;

  /// Il existe une consultation logique à reprendre (indépendant de la fenêtre
  /// de 5 min et de `expiresAt`). Sert au chargement de l'historique.
  bool get hasResumableConsultation => _active != null;

  /// Session exploitable maintenant : consultation présente ET du temps
  /// disponible. Pilote la bannière « Reprendre ma consultation » et l'entrée
  /// directe dans le chat.
  bool get hasActiveSession => _active != null && _walletSeconds > 0;

  /// Fenêtre de facturation de 5 min en cours (statut « consultation en
  /// cours »). Hors fenêtre, la consultation N'est PAS finie.
  bool get windowActive => _time?.windowActive ?? false;
  DateTime? get windowExpiresAt => _time?.windowExpiresAt;

  /// Temps total restant, jamais négatif.
  Duration get remaining => Duration(seconds: _walletSeconds);

  /// Libellé UNIQUE du « temps disponible » — MÊME vérité que l'Accueil
  /// (`HomeScreen._timeValueFor(_deriveState(...))`). Le serveur reste
  /// autoritaire : on ne fait que PRÉSENTER, aucun nouveau calcul métier.
  ///   session active                       -> portefeuille formaté
  ///   1re heure offerte pas encore consommée -> « 1 h offerte »
  ///     (le backend ne crédite les 3600 s au portefeuille qu'à l'ouverture de
  ///      la 1re consultation ; d'ici là `first_free_available` = true et les
  ///      buckets sont à 0 — l'Accueil affiche déjà « 1 h offerte », pas « 0 min »)
  ///   portefeuille vide                    -> « 0 min »
  ///   sinon                                -> portefeuille formaté
  String get availableTimeLabel {
    if (hasActiveSession) return formatTotalTime(_walletSeconds);
    final q = _quota;
    if (q?.firstFreeAvailable == true) return '1 h offerte';
    final t = _time;
    if (t != null) {
      return t.hasTime ? formatTotalTime(_walletSeconds) : '0 min';
    }
    // Fallback backend ancien (bloc `time` absent).
    if (q == null) return '1 h offerte';
    if ((q.isPremium && q.monthlyRemaining > 0) || q.earnedAvailable > 0) {
      return formatTotalTime(_walletSeconds);
    }
    return '0 min';
  }

  /// Portefeuille d'heures : « 8 h », « 7 h 42 min », « 42 min », « < 1 min »,
  /// « 0 min ». Pas de countdown seconde par seconde sur ce total.
  static String formatTotalTime(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    if (s == 0) return '0 min';
    if (s < 60) return '< 1 min';
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h == 0) return '$m min';
    if (m == 0) return '$h h';
    return '$h h ${m.toString().padLeft(2, '0')} min';
  }

  /// COMPAT — ancienne signature `Duration`. Redirige vers [formatTotalTime].
  static String formatRemaining(Duration d) =>
      formatTotalTime(d.isNegative ? 0 : d.inSeconds);

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
      _time = res.time; // null si backend ancien -> fallback [_walletSeconds]
      _refreshError = null;
      _syncTimer();
    } on ApiUnauthorizedException {
      _active = null;
      _time = null;
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

  /// J6 — recharge la LISTE des fils (`GET /api/consultation/list`). Distinct de
  /// [refresh] (qui ne synchronise que le portefeuille via `/state`).
  ///
  ///  - pas de jeton -> aucun appel.
  ///  - 200 -> `consultations` remplacée par la liste serveur.
  ///  - réseau / 5xx / 401 -> on CONSERVE la liste connue, on note
  ///    [consultationsError] et on ne purge/ne déconnecte JAMAIS (un `/list`
  ///    indisponible ne doit pas sortir l'utilisateur de l'app).
  Future<void> refreshConsultations() async {
    if (_consultationsLoading || _disposed) return;

    final token = await _auth.currentToken();
    if (token == null || token.isEmpty || _disposed) return;

    _consultationsLoading = true;
    _consultationsError = null;
    notifyListeners();

    try {
      final list = await _api.listConsultations(bearer: token);
      if (_disposed) return;
      _consultations = list;
      _consultationsError = null;
    } on ApiUnauthorizedException catch (e) {
      // Volontaire : un échec de /list ne déconnecte pas (cf. J6-F1 §E).
      _consultationsError = e;
    } on ApiNetworkException catch (e) {
      _consultationsError = e;
    } on ApiException catch (e) {
      _consultationsError = e;
    } catch (e) {
      _consultationsError = e;
    } finally {
      _consultationsLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// J6 — synchronise le portefeuille (`/state`) PUIS la liste (`/list`). Un
  /// échec de l'un n'annule pas l'autre. Pratique pour un « pull-to-refresh »
  /// unique côté UI ; `refresh()` seul reste inchangé pour les appelants
  /// existants.
  Future<void> refreshAll() async {
    await refresh();
    await refreshConsultations();
  }

  /// J6 — ouvre / reprend la discussion avec [advisorId] via
  /// `POST /api/consultation/open`, puis rafraîchit [consultations]. Retourne le
  /// [ConsultationDto] du fil — EXISTANT (backend renvoie le fil du conseiller)
  /// OU neuf (`openedNow`).
  ///
  /// Ne modifie PAS `AuryelState.selectedAdvisor`, ne PATCH aucun profil, ne
  /// consomme aucun temps, ne crée aucun timer local. Lève une
  /// [ApiUnauthorizedException] s'il n'y a pas de jeton ; propage les autres
  /// erreurs API à l'appelant (l'UI décidera de l'affichage).
  Future<ConsultationDto> openAdvisor(String advisorId) async {
    final token = await _auth.currentToken();
    if (token == null || token.isEmpty) {
      throw ApiUnauthorizedException();
    }
    final dto = await _api.openConsultation(
      bearer: token,
      advisorId: advisorId,
    );
    await refreshConsultations();
    return dto;
  }

  /// Injection immédiate de l'état après un `POST /api/consultation/message`
  /// réussi (le ChatScreen a déjà la réponse en main : pas de re-GET).
  void updateFromMessageResponse(ConsultationMessageResponse res) {
    final hadSession = _active != null;
    if (res.consultation != null) {
      _active = res.consultation;
    }
    // Meta : « consultation démarrée » — le serveur vient de créer la session
    // (transition « aucune session » -> session active au 1er message accepté).
    // No-op sans consentement. Aucune donnée : ni message, ni conseiller, ni id.
    if (!hadSession && _active != null) {
      unawaited(_meta.logConsultationStarted());
    }
    _quota = res.quota;
    if (res.time != null) _time = res.time;
    _refreshError = null;
    _syncTimer();
    notifyListeners();
  }

  /// Resynchro après un 402 (`time_exhausted` — cas principal — ou l'ancien
  /// `no_credit`). Met à jour `time` + `quota` du corps du 402 SANS jamais
  /// fabriquer de session active.
  void applyExhausted({ConsultationTimeState? time, QuotaDto? quota}) {
    if (time != null) _time = time;
    if (quota != null) _quota = quota;
    _syncTimer();
    notifyListeners();
  }

  /// COMPAT — ancien point d'entrée `no_credit` (quota seul).
  void applyNoCredit(QuotaDto? quota) => applyExhausted(quota: quota);

  /// AUDIT ABONNEMENT — à appeler explicitement sur DÉCONNEXION, AVANT toute
  /// navigation vers l'écran de connexion. Vide tout état connu (session,
  /// quota/Premium, temps, liste des fils) pour qu'un statut Premium de
  /// l'ancien compte ne puisse jamais s'afficher — même un instant — pour le
  /// compte suivant qui se connectera sur cet appareil. Le prochain
  /// [refresh] / [refreshAll] (déclenché par le flux de connexion) repart
  /// donc de zéro, jamais d'un résidu de l'ancienne session. N'appelle aucun
  /// réseau, ne touche pas le jeton (déjà purgé par `AuthController.logout`).
  void reset() {
    if (_disposed) return;
    _active = null;
    _quota = null;
    _time = null;
    _refreshError = null;
    _consultations = const [];
    _consultationsError = null;
    _syncTimer();
    notifyListeners();
  }

  void _syncTimer() {
    _ticker?.cancel();
    _ticker = null;
    if (_disposed) return;
    // Le tick ne sert QU'au rafraîchissement du statut « fenêtre active » :
    // inutile hors fenêtre (le total d'heures ne descend pas côté client).
    if (windowActive) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_disposed || !windowActive) {
          _ticker?.cancel();
          _ticker = null;
          return;
        }
        notifyListeners();
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
    final scope = context
        .dependOnInheritedWidgetOfExactType<ConsultationScope>();
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
