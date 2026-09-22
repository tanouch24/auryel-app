// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../api/unread_api.dart';
import '../services/launcher_badge_channel.dart';

class UnreadController extends ChangeNotifier {
  // The public parameter name must stay `badgeChannel`; the field is private
  // so callers cannot use an initializing formal across library boundaries.
  UnreadController({
    required this._api,
    required this._tokenProvider,
    LauncherBadgeChannel? badgeChannel,
  }) : _badgeChannel = badgeChannel;

  final UnreadApi _api;
  final Future<String?> Function() _tokenProvider;
  final LauncherBadgeChannel? _badgeChannel;
  Map<String, int> _counts = const {};
  final Set<String> _consultationAdvisorIds = <String>{};
  bool _refreshing = false;
  int _sessionGeneration = 0;

  int count(String category) => _counts[category] ?? 0;
  int get consultation => count('consultation');
  int get wellbeing => count('wellbeing');
  Set<String> get consultationAdvisorIds =>
      Set.unmodifiable(_consultationAdvisorIds);

  void noteConsultationAdvisor(String? advisorId) {
    final normalized = advisorId?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return;
    if (_consultationAdvisorIds.add(normalized)) notifyListeners();
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    final requestGeneration = _sessionGeneration;
    try {
      final token = await _tokenProvider();
      if (token == null || token.isEmpty) return;
      final counts = await _api.counts(bearer: token);
      if (requestGeneration != _sessionGeneration) return;
      _counts = counts;
      if (consultation == 0) _consultationAdvisorIds.clear();
      notifyListeners();
      await _syncBadge();
    } on ApiUnauthorizedException {
      clear();
    } on ApiException {
      // Les badges ne doivent jamais bloquer l'application.
    } on ApiNetworkException {
      // L'état connu reste affiché jusqu'au prochain rafraîchissement.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> markRead(String category) async {
    final requestGeneration = _sessionGeneration;
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) return;
    try {
      await _api.markRead(category, bearer: token);
      if (requestGeneration != _sessionGeneration) return;
      if (_counts.containsKey(category)) {
        final next = Map<String, int>.from(_counts)..[category] = 0;
        _counts = next;
        if (category == 'consultation') _consultationAdvisorIds.clear();
        notifyListeners();
      }
      await _syncBadge();
      await refresh();
    } on ApiUnauthorizedException {
      clear();
    } on ApiException {
      // L'ouverture reste utilisable même si la synchronisation échoue.
    } on ApiNetworkException {
      // Réessai au prochain refresh.
    }
  }

  void clear() {
    _sessionGeneration++;
    final hadState = _counts.isNotEmpty || _consultationAdvisorIds.isNotEmpty;
    _counts = const {};
    _consultationAdvisorIds.clear();
    if (hadState) notifyListeners();
    unawaited(_syncBadge());
  }

  Future<void> _syncBadge() async {
    final count = consultation + wellbeing;
    try {
      await _badgeChannel?.sync(count);
    } catch (_) {
      // A launcher/plugin failure is never a consultation failure.
    }
  }
}

class UnreadScope extends InheritedNotifier<UnreadController> {
  const UnreadScope({
    super.key,
    required UnreadController controller,
    required super.child,
  }) : super(notifier: controller);

  static UnreadController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UnreadScope>()?.notifier;

  static UnreadController? maybeReadOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<UnreadScope>()?.notifier;
}
