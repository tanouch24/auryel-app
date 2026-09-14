// Public constructor names keep the API readable while private fields stay
// encapsulated; the assignment is intentional.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../api/wellbeing_program_api.dart';

class WellbeingProgramController extends ChangeNotifier {
  WellbeingProgramController({
    required WellbeingProgramApi api,
    required Future<String?> Function() tokenProvider,
  }) : _api = api,
       _tokenProvider = tokenProvider;

  final WellbeingProgramApi _api;
  final Future<String?> Function() _tokenProvider;
  WellbeingProgramState? _state;
  Object? _error;
  bool _loading = true;
  bool _busy = false;
  bool _disposed = false;

  WellbeingProgramState? get state => _state;
  Object? get error => _error;
  bool get loading => _loading && _state == null;
  bool get busy => _busy;

  Future<void> refresh() => _run((token) => _api.getProgram(token));
  Future<void> start() => _run((token) => _api.start(token));

  Future<void> completeAction(int dayNumber, int actionSlot) => _run(
    (token) => _api.completeAction(
      bearer: token,
      dayNumber: dayNumber,
      actionSlot: actionSlot,
    ),
  );

  Future<void> setReminder(bool enabled) =>
      _run((token) => _api.setReminder(bearer: token, enabled: enabled));

  Future<void> _run(
    Future<WellbeingProgramState> Function(String token) request,
  ) async {
    if (_busy || _disposed) return;
    final token = await _tokenProvider();
    if (token == null || token.isEmpty || _disposed) return;
    _busy = true;
    _loading = true;
    _error = null;
    _notify();
    try {
      final next = await request(token);
      if (!_disposed) _state = next;
    } on ApiException catch (error) {
      _error = error;
    } on ApiNetworkException catch (error) {
      _error = error;
    } catch (error) {
      _error = error;
    } finally {
      _busy = false;
      _loading = false;
      _notify();
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

class WellbeingProgramScope
    extends InheritedNotifier<WellbeingProgramController> {
  const WellbeingProgramScope({
    super.key,
    required WellbeingProgramController controller,
    required super.child,
  }) : super(notifier: controller);

  static WellbeingProgramController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WellbeingProgramScope>()
      ?.notifier;

  static WellbeingProgramController? maybeReadOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<WellbeingProgramScope>()?.notifier;
}
