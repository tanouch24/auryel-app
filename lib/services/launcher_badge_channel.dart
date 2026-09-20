import 'package:flutter/services.dart';

/// Synchronise le badge launcher Android avec les compteurs unread serveur.
/// Les launchers qui ne supportent pas les badges ignorent naturellement cette
/// demande ; l'échec ne doit jamais affecter l'application.
abstract class LauncherBadgeChannel {
  Future<void> sync(int count);
}

class MethodChannelLauncherBadge implements LauncherBadgeChannel {
  MethodChannelLauncherBadge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('auryel/wake_alarm');

  final MethodChannel _channel;

  @override
  Future<void> sync(int count) async {
    try {
      await _channel.invokeMethod<void>('syncLauncherBadge', {
        'count': count < 0 ? 0 : count,
      });
    } catch (_) {
      // Badge launcher non supporté, permission refusée ou ancienne build :
      // aucun chemin produit ne doit tomber en panne.
    }
  }
}
