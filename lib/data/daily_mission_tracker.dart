import 'package:shared_preferences/shared_preferences.dart';

/// Suivi LOCAL et minimal de l'accomplissement des « missions du jour »
/// (routine quotidienne). Une entrée par mission = la date locale
/// (`YYYY-MM-DD`) du dernier accomplissement. Une valeur qui n'est plus celle
/// d'aujourd'hui est traitée comme « non fait » -> reset logique automatique au
/// changement de jour, sans aucun timer minuit (recalcul à l'ouverture de la
/// Home / au retour en avant-plan).
///
/// Ce tracker sert UNIQUEMENT à afficher la coche. Il ne crédite AUCUN temps de
/// consultation, AUCUNE récompense, AUCUN achat, AUCUN abonnement — il n'a
/// d'ailleurs aucun moyen technique de le faire (SharedPreferences local).
///
/// Missions gérées ici :
///  - `tirage`       : coché quand un tirage a réellement été sauvegardé ;
///  - `consultation` : coché quand une activité de consultation réelle est
///                     détectée (fenêtre de facturation / session active) ;
///  - `moment`       : coché UNIQUEMENT sur une séance « Ton Moment »
///                     réellement aboutie (fin naturelle de l'audio ou ≥ 90 %
///                     écoutés — cf. MeditationScreen). JAMAIS à la simple
///                     ouverture de l'onglet, ni sur une écoute de quelques
///                     secondes. Une fois par jour.
/// Le partage N'EST PAS géré ici : il s'appuie sur `DailyShareTracker`.
class DailyMissionTracker {
  DailyMissionTracker({SharedPreferences? prefs}) : _injected = prefs;

  static const String tirage = 'tirage';
  static const String consultation = 'consultation';
  static const String moment = 'moment';

  final SharedPreferences? _injected;

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  static String _key(String mission) => 'auryel.daily_mission.$mission';

  static String _day(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  /// `true` si [mission] a été accomplie AUJOURD'HUI (date locale).
  Future<bool> isDone(String mission, {DateTime? now}) async {
    final prefs = await _prefs;
    final today = _day(now ?? DateTime.now());
    return prefs.getString(_key(mission)) == today;
  }

  /// Marque [mission] comme accomplie pour la journée locale courante.
  /// Idempotent : réécrire la même valeur ne change rien.
  Future<void> markDone(String mission, {DateTime? now}) async {
    final prefs = await _prefs;
    await prefs.setString(_key(mission), _day(now ?? DateTime.now()));
  }
}
