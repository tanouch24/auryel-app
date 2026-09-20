import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lastAnnouncedBuildKey = 'auryel_last_announced_build_v1';

class AppUpdateAlertService {
  AppUpdateAlertService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('auryel/wake_alarm');

  final MethodChannel _channel;

  Future<String?> currentBuild() async {
    try {
      final value = await _channel.invokeMethod<String>('getAppVersion');
      final build = value?.trim();
      return build == null || build.isEmpty ? null : build;
    } catch (_) {
      return null;
    }
  }

  /// Returns true only for a build that was previously seen and differs from
  /// the last build announced. First install is deliberately silent.
  static Future<bool> claimUpdate({
    required SharedPreferences preferences,
    required String build,
  }) async {
    final normalized = build.trim();
    if (normalized.isEmpty) return false;
    final previous = preferences.getString(_lastAnnouncedBuildKey);
    if (previous == null) {
      await preferences.setString(_lastAnnouncedBuildKey, normalized);
      return false;
    }
    if (previous == normalized) return false;
    final persisted = await preferences.setString(
      _lastAnnouncedBuildKey,
      normalized,
    );
    return persisted;
  }

  Future<void> showIfNeeded(BuildContext context) async {
    try {
      final build = await currentBuild();
      if (build == null || !context.mounted) return;
      final preferences = await SharedPreferences.getInstance();
      final previous = preferences.getString(_lastAnnouncedBuildKey);
      if (previous == null) {
        await preferences.setString(_lastAnnouncedBuildKey, build);
        return;
      }
      if (previous == build) return;
      if (!await preferences.setString(_lastAnnouncedBuildKey, build) ||
          !context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Auryel a été mis à jour ✨'),
          content: const Text('Découvre les nouveautés de cette version.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fermer'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Découvrir'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Le stockage ou le canal peuvent être indisponibles : le démarrage
      // reste totalement utilisable.
    }
  }
}
