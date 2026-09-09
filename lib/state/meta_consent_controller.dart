// Paramètres nommés publics de nom différent des champs privés.
// ignore_for_file: prefer_initializing_formals
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analytics/meta_events.dart';

/// État du consentement à la mesure publicitaire Meta.
///
/// - Persisté localement (`shared_preferences`), défaut **false** (jamais
///   pré-coché).
/// - Toute bascule applique immédiatement le consentement au [MetaEvents]
///   (activation / purge SDK).
/// - Révocable à tout moment depuis « Mon compte ».
class MetaConsentController extends ChangeNotifier {
  MetaConsentController({
    required MetaEvents events,
    SharedPreferences? prefs,
  })  : _events = events,
        _prefs = prefs;

  static const String storageKey = 'auryel_meta_consent_v1';

  final MetaEvents _events;
  SharedPreferences? _prefs;

  bool _granted = false;
  bool get granted => _granted;

  /// `true` si la mesure Meta est réellement active (config + consentement).
  bool get measurementActive => _events.isActive;

  /// À appeler au démarrage : lit la valeur persistée (défaut false) — le
  /// [MetaEvents] a déjà été créé avec cette valeur, on ne fait que refléter
  /// l'état.
  Future<void> load() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      _granted = _prefs?.getBool(storageKey) ?? false;
    } catch (_) {
      _granted = false;
    }
    notifyListeners();
  }

  /// Bascule explicite de l'utilisateur. Persiste puis applique.
  Future<void> setGranted(bool value) async {
    if (_granted == value) return;
    _granted = value;
    notifyListeners();
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setBool(storageKey, value);
    } catch (_) {
      /* persistance best-effort */
    }
    await _events.setConsent(value);
    notifyListeners();
  }

  /// Lit la valeur persistée SANS instance de contrôleur (pour la fabrique
  /// [MetaEvents.create] au démarrage).
  static Future<bool> readPersisted() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(storageKey) ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Fournit [MetaEvents] + [MetaConsentController] à l'arbre. Absent des tests
/// hérités -> `maybeOf` renvoie `null` (aucune mesure).
class AnalyticsScope extends InheritedNotifier<MetaConsentController> {
  const AnalyticsScope({
    super.key,
    required this.events,
    required MetaConsentController controller,
    required super.child,
  }) : super(notifier: controller);

  final MetaEvents events;

  static MetaEvents eventsOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AnalyticsScope>()
          ?.events ??
      const NoopMetaEvents();

  static MetaConsentController? consentOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AnalyticsScope>()?.notifier;
}
