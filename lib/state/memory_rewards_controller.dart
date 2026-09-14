// Champs privés injectés par des paramètres nommés publics.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/memory_api.dart';

/// État des récompenses du Jeu Auryel (Memory).
///
/// Le SERVEUR est l'unique autorité : [progress] vient de
/// `GET /api/app/memory/progress`, [startGame] ouvre une partie serveur et
/// [completeGame] la ferme + décide de la récompense. RIEN n'est calculé ni
/// persisté localement — le jeu reste entièrement jouable même si tous ces
/// appels échouent (aucun faux crédit côté client).
class MemoryRewardsController extends ChangeNotifier {
  MemoryRewardsController({
    required MemoryApi api,
    required Future<String?> Function() tokenProvider,
  }) : _api = api,
       _token = tokenProvider;

  final MemoryApi _api;
  final Future<String?> Function() _token;

  MemoryProgress? _progress;
  bool _loading = true;
  bool _busy = false;
  Object? _error;
  bool _disposed = false;

  /// Dernière progression connue (null tant qu'aucun chargement n'a abouti).
  MemoryProgress? get progress => _progress;

  /// Chargement initial en cours (aucune donnée encore).
  bool get loading => _loading && _progress == null;

  /// Un appel réseau (refresh / start / complete) est en cours.
  bool get busy => _busy;

  /// Dernier échec réseau / API. Non bloquant : le jeu reste jouable.
  Object? get error => _error;

  /// GROS CHANTIER AURYEL (Prompt 3/5) — éligibilité PARTAGÉE par toute la
  /// catégorie mini-jeux (Memory / Suite intuitive / Carte cachée) : `true`
  /// tant qu'aucune n'a encore été récompensée aujourd'hui. `null` tant que
  /// la progression n'est pas encore chargée (jamais un faux « verrouillé »
  /// par défaut).
  bool? get eligibleToday => _progress?.eligibleToday;

  /// Montant Étoiles de la règle `mini_game_completed`, résolu serveur.
  int get starsReward => _progress?.starsReward ?? 0;

  /// ISO-8601 du prochain reset (minuit Europe/Paris), `null` si éligible.
  String? get nextResetAt => _progress?.nextResetAt;

  /// `GET /api/app/memory/progress`. Ne récompense jamais. Conserve la dernière
  /// progression connue en cas d'échec.
  Future<void> refresh() async {
    if (_busy || _disposed) return;
    final token = await _token();
    if (token == null || token.isEmpty || _disposed) return;

    _busy = true;
    _loading = true;
    _error = null;
    _notify();
    try {
      final p = await _api.getProgress(token);
      if (_disposed) return;
      _progress = p;
      _error = null;
    } on ApiException catch (e) {
      _error = e;
    } on ApiNetworkException catch (e) {
      _error = e;
    } catch (e) {
      _error = e;
    } finally {
      _busy = false;
      _loading = false;
      _notify();
    }
  }

  /// Ouvre une partie serveur. Renvoie la session (avec `gameId`) ou `null` si
  /// l'appel échoue — dans ce cas le jeu se lance quand même, sans récompense.
  Future<MemoryGameSession?> startGame(String apiDifficulty) async {
    if (_disposed) return null;
    final token = await _token();
    if (token == null || token.isEmpty) return null;

    _busy = true;
    _error = null;
    _notify();
    try {
      final s = await _api.start(bearer: token, difficulty: apiDifficulty);
      _error = null;
      return s;
    } on ApiException catch (e) {
      _error = e;
      return null;
    } on ApiNetworkException catch (e) {
      _error = e;
      return null;
    } catch (e) {
      _error = e;
      return null;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Ferme une partie serveur : le serveur calcule le chrono, applique le seuil
  /// et l'éligibilité 7 j, crédite éventuellement. Renvoie le résultat ou
  /// `null` si l'appel échoue (le jeu affiche alors sa fin « neutre »).
  ///
  /// En cas de succès, [refresh] est relancé pour rafraîchir l'éligibilité.
  Future<MemoryCompleteResult?> completeGame(String gameId) async {
    if (_disposed) return null;
    final token = await _token();
    if (token == null || token.isEmpty) return null;

    _busy = true;
    _error = null;
    _notify();
    MemoryCompleteResult? result;
    try {
      result = await _api.complete(bearer: token, gameId: gameId);
      _error = null;
    } on ApiException catch (e) {
      _error = e;
    } on ApiNetworkException catch (e) {
      _error = e;
    } catch (e) {
      _error = e;
    } finally {
      _busy = false;
      _notify();
    }
    if (result != null && !_disposed) {
      // éligibilité potentiellement modifiée -> resynchro (silencieuse).
      unawaitedRefresh();
    }
    return result;
  }

  /// [refresh] sans attendre (fire-and-forget) — pour resynchroniser après un
  /// `completeGame`.
  void unawaitedRefresh() {
    // ignore: discarded_futures
    refresh();
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
