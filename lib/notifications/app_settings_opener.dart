import 'package:permission_handler/permission_handler.dart' as ph;

/// Ouvre la page « Réglages » système de l'app (pour ré-autoriser les
/// notifications après un refus). Utilisé UNIQUEMENT quand le statut est
/// `denied` (donc infra push active).
abstract class AppSettingsOpener {
  Future<void> open();
}

/// Implémentation réelle : `permission_handler.openAppSettings()`.
class SystemAppSettingsOpener implements AppSettingsOpener {
  const SystemAppSettingsOpener();

  @override
  Future<void> open() async {
    try {
      await ph.openAppSettings();
    } catch (_) {
      /* plateforme non supportée / test -> no-op */
    }
  }
}

/// Inerte — tests / écrans montés isolément.
class NoopAppSettingsOpener implements AppSettingsOpener {
  const NoopAppSettingsOpener();

  @override
  Future<void> open() async {}
}
