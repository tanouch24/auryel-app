// ignore_for_file: prefer_initializing_formals

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/wellbeing_ebooks_api.dart';

class WellbeingEbooksController extends ChangeNotifier {
  WellbeingEbooksController({
    required WellbeingEbooksApi api,
    required Future<String?> Function() tokenProvider,
    bool Function()? authReadyProvider,
  }) : _api = api,
       _tokenProvider = tokenProvider,
       _authReadyProvider = authReadyProvider;

  final WellbeingEbooksApi _api;
  final Future<String?> Function() _tokenProvider;
  final bool Function()? _authReadyProvider;
  List<WellbeingEbook> _ebooks = const [];
  Object? _error;
  bool _loading = true;
  bool _sessionUnavailable = false;
  bool _disposed = false;
  Future<void>? _refreshInFlight;
  DateTime? _catalogReadyAt;

  List<WellbeingEbook> get ebooks => _ebooks;
  Object? get error => _error;
  bool get loading => _loading;
  bool get sessionUnavailable => _sessionUnavailable;
  bool get sessionExpired => _error is ApiUnauthorizedException;
  DateTime? get catalogReadyAt => _catalogReadyAt;

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final future = _refreshInternal();
    _refreshInFlight = future;
    future.then<void>(
      (_) => _clearInFlight(future),
      onError: (Object error, StackTrace stack) => _clearInFlight(future),
    );
    return future;
  }

  Future<void> _refreshInternal() async {
    final stopwatch = Stopwatch()..start();
    final token = await _tokenProvider();
    if (token == null || token.isEmpty || _disposed) {
      if (!_disposed && (_authReadyProvider?.call() ?? true)) {
        _sessionUnavailable = true;
        _loading = false;
        _error = null;
        notifyListeners();
      }
      _debugTiming('auth unavailable', stopwatch);
      return;
    }
    _sessionUnavailable = false;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _ebooks = await _api.getCatalog(token);
      _catalogReadyAt = DateTime.now();
    } on ApiException catch (error) {
      _error = error;
      _debugError(error);
    } on ApiNetworkException catch (error) {
      _error = error;
      _debugError(error);
    } catch (error) {
      _error = error;
      _debugError(error);
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
      _debugTiming('refresh complete (${_ebooks.length} ebooks)', stopwatch);
    }
  }

  void _clearInFlight(Future<void> future) {
    if (identical(_refreshInFlight, future)) _refreshInFlight = null;
  }

  void _debugTiming(String phase, Stopwatch stopwatch) {
    if (kDebugMode) {
      debugPrint('[ebooks] $phase ${stopwatch.elapsedMilliseconds}ms');
    }
  }

  void _debugError(Object error) {
    if (!kDebugMode) return;
    if (error is ApiException) {
      debugPrint('[ebooks] erreur HTTP ${error.statusCode} code=${error.code ?? "none"}');
    } else {
      debugPrint('[ebooks] erreur ${error.runtimeType}');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class WellbeingEbooksScope
    extends InheritedNotifier<WellbeingEbooksController> {
  const WellbeingEbooksScope({
    super.key,
    required WellbeingEbooksController controller,
    required super.child,
  }) : super(notifier: controller);

  static WellbeingEbooksController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WellbeingEbooksScope>()
      ?.notifier;
}
