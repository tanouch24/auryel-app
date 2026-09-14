// ignore_for_file: prefer_initializing_formals

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../api/wellbeing_ebooks_api.dart';

class WellbeingEbooksController extends ChangeNotifier {
  WellbeingEbooksController({
    required WellbeingEbooksApi api,
    required Future<String?> Function() tokenProvider,
  }) : _api = api,
       _tokenProvider = tokenProvider;

  final WellbeingEbooksApi _api;
  final Future<String?> Function() _tokenProvider;
  List<WellbeingEbook> _ebooks = const [];
  Object? _error;
  bool _loading = true;
  bool _disposed = false;

  List<WellbeingEbook> get ebooks => _ebooks;
  Object? get error => _error;
  bool get loading => _loading;

  Future<void> refresh() async {
    if (_disposed) return;
    final token = await _tokenProvider();
    if (token == null || token.isEmpty || _disposed) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _ebooks = await _api.getCatalog(token);
    } on ApiException catch (error) {
      _error = error;
    } on ApiNetworkException catch (error) {
      _error = error;
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
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
