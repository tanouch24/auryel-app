import 'package:flutter/foundation.dart';

/// Traces de démarrage opt-in, sans données utilisateur ni secrets.
/// Activé uniquement avec --dart-define=AURYEL_STARTUP_TRACE=true.
class StartupTrace {
  StartupTrace._();

  static const enabled = bool.fromEnvironment(
    'AURYEL_STARTUP_TRACE',
    defaultValue: false,
  );
  static final Stopwatch _clock = Stopwatch()..start();

  static void mark(String step) {
    if (enabled) {
      debugPrint('AURYEL_STARTUP ${_clock.elapsedMilliseconds}ms $step');
    }
  }
}
