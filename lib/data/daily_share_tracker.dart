import 'package:shared_preferences/shared_preferences.dart';

/// Comptage LOCAL des jours où l'utilisateur a déclenché un partage du message
/// du jour — **1 jour compté au maximum par jour calendaire**.
///
/// B8.1 ne fait QUE compter. AUCUNE logique de récompense ici :
///  - pas d'attribution d'heure,
///  - pas de modification de `purchased_seconds` / du portefeuille de temps,
///  - pas d'appel backend.
///
/// POINT D'ACCROCHE B10 (Dashboard / récompenses) : B10 lira
/// [sharedDaysCount] (progression « X / 30 ») et, quand le seuil produit validé
/// est atteint, déclenchera lui-même l'attribution de +1 h. B8.1 se contente de
/// tenir le compteur à jour via [recordShareAttempt].
class DailyShareTracker {
  DailyShareTracker({SharedPreferences? prefs}) : _injected = prefs;

  static const String _daysKey = 'auryel.daily_share.days';

  final SharedPreferences? _injected;

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  static String _dayKey(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  /// Enregistre une TENTATIVE de partage. Le jour courant n'est compté qu'une
  /// fois : renvoie `true` s'il s'agit d'un NOUVEAU jour (le compteur a
  /// augmenté), `false` si le partage d'aujourd'hui était déjà compté.
  Future<bool> recordShareAttempt({DateTime? now}) async {
    final prefs = await _prefs;
    final today = _dayKey(now ?? DateTime.now());
    final days = prefs.getStringList(_daysKey) ?? const <String>[];
    if (days.contains(today)) return false;
    await prefs.setStringList(_daysKey, <String>[...days, today]);
    return true;
  }

  /// Nombre de jours DISTINCTS où un partage a été déclenché. C'est la valeur
  /// que B10 utilisera pour la progression « X / 30 ».
  Future<int> sharedDaysCount() async {
    final prefs = await _prefs;
    return (prefs.getStringList(_daysKey) ?? const <String>[]).toSet().length;
  }

  /// `true` si le partage d'aujourd'hui est déjà compté (sert à adapter le
  /// libellé du bouton, pas à bloquer le partage natif lui-même).
  Future<bool> sharedToday({DateTime? now}) async {
    final prefs = await _prefs;
    final today = _dayKey(now ?? DateTime.now());
    return (prefs.getStringList(_daysKey) ?? const <String>[]).contains(today);
  }
}
