/// Ouvre la page « Réglages » système de l'app (pour ré-autoriser les
/// notifications après un refus).
///
/// DÉPENDANCE PLUGIN : ceci nécessite `permission_handler`
/// (`openAppSettings()`) ou `app_settings` — **non ajouté dans ce lot** (aucune
/// nouvelle dépendance). L'implémentation par défaut [NoopAppSettingsOpener] ne
/// fait rien ; l'entrée « Ouvrir les réglages » n'apparaît de toute façon que
/// si l'autorisation est `denied`, ce qui suppose une infra push active
/// (Firebase configuré). Aujourd'hui le statut est `unavailable` -> l'entrée
/// n'est jamais un faux bouton actif.
abstract class AppSettingsOpener {
  Future<void> open();
}

class NoopAppSettingsOpener implements AppSettingsOpener {
  const NoopAppSettingsOpener();

  @override
  Future<void> open() async {
    /* plugin non câblé -> no-op */
  }
}
