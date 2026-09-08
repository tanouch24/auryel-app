import 'package:shared_preferences/shared_preferences.dart';

/// « J'aime » LOCAL du message du jour — un état booléen par jour calendaire.
///
/// B8.2 : purement local (`SharedPreferences`), aucun backend, aucune récompense.
/// Sert à un geste léger sur l'accueil (cœur). B10 / analytics pourront lire
/// [likedDaysCount] plus tard si besoin ; B8.2 ne fait que persister l'état.
class DailyLikeStore {
  DailyLikeStore({this.bucket = 'message', SharedPreferences? prefs})
      : _injected = prefs;

  /// Espace de nommage : « message » (message du jour, accueil + feuille) ou
  /// « tarot » (tirage du jour). Deux compteurs indépendants, même mécanique.
  final String bucket;

  String get _daysKey => 'auryel.daily_like.$bucket.days';

  final SharedPreferences? _injected;

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  static String _dayKey(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  /// `true` si le message d'aujourd'hui est marqué « aimé ».
  Future<bool> isLikedToday({DateTime? now}) async {
    final prefs = await _prefs;
    final today = _dayKey(now ?? DateTime.now());
    return (prefs.getStringList(_daysKey) ?? const <String>[]).contains(today);
  }

  /// Bascule l'état pour aujourd'hui et renvoie le nouvel état (`true` = aimé).
  Future<bool> toggleToday({DateTime? now}) async {
    final prefs = await _prefs;
    final today = _dayKey(now ?? DateTime.now());
    final days = <String>[
      ...(prefs.getStringList(_daysKey) ?? const <String>[]),
    ];
    final bool nowLiked;
    if (days.contains(today)) {
      days.remove(today);
      nowLiked = false;
    } else {
      days.add(today);
      nowLiked = true;
    }
    await prefs.setStringList(_daysKey, days);
    return nowLiked;
  }

  /// Nombre de jours distincts marqués « aimé » (usage futur B10 / analytics).
  Future<int> likedDaysCount() async {
    final prefs = await _prefs;
    return (prefs.getStringList(_daysKey) ?? const <String>[]).toSet().length;
  }
}
