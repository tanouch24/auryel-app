import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../api/unread_api.dart';

class UnreadController extends ChangeNotifier {
  UnreadController({
    required this._api,
    required this._tokenProvider,
  });

  final UnreadApi _api;
  final Future<String?> Function() _tokenProvider;
  Map<String, int> _counts = const {};
  bool _refreshing = false;

  int count(String category) => _counts[category] ?? 0;
  int get consultation => count('consultation');
  int get wellbeing => count('wellbeing');

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final token = await _tokenProvider();
      if (token == null || token.isEmpty) return;
      _counts = await _api.counts(bearer: token);
      notifyListeners();
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
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) return;
    try {
      await _api.markRead(category, bearer: token);
      if (_counts.containsKey(category)) {
        final next = Map<String, int>.from(_counts)..[category] = 0;
        _counts = next;
        notifyListeners();
      }
    } on ApiUnauthorizedException {
      clear();
    } on ApiException {
      // L'ouverture reste utilisable même si la synchronisation échoue.
    } on ApiNetworkException {
      // Réessai au prochain refresh.
    }
  }

  void clear() {
    if (_counts.isEmpty) return;
    _counts = const {};
    notifyListeners();
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
