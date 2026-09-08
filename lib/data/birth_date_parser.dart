/// Parsing d'une date de naissance saisie librement par l'utilisateur.
///
/// Séparé de tout widget pour être testable unitairement. Accepte, entre
/// autres :
///
///   17 mai 2000        17052000        17-05-2000
///   17/05/2000         17 05 2000      17.05.2000
///   17 MAI 2000        17 février 2000 17 fevrier 2000
///
/// Règle numérique : JOUR / MOIS / ANNÉE (donc `05/06/2000` = 5 juin 2000).
///
/// Renvoie une [DateTime] normalisée à minuit (heure locale), directement
/// compatible avec le format ISO `YYYY-MM-DD` envoyé ensuite au backend
/// (`PATCH /api/app/profile`). Renvoie `null` pour toute saisie vide,
/// incomplète, ambiguë, impossible (31/02, 32/01, 29/02 hors année
/// bissextile) ou située dans le futur.
library;

const Map<String, int> _monthsByName = {
  'janvier': 1,
  'fevrier': 2,
  'mars': 3,
  'avril': 4,
  'mai': 5,
  'juin': 6,
  'juillet': 7,
  'aout': 8,
  'septembre': 9,
  'octobre': 10,
  'novembre': 11,
  'decembre': 12,
};

const List<String> _frMonthLabels = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

const Map<String, String> _accentFolding = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'ç': 'c',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ñ': 'n',
};

String _foldAccents(String input) {
  final buffer = StringBuffer();
  for (final ch in input.split('')) {
    buffer.write(_accentFolding[ch] ?? ch);
  }
  return buffer.toString();
}

bool _isLeapYear(int year) =>
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

int _daysInMonth(int month, int year) {
  const lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month == 2 && _isLeapYear(year)) return 29;
  return lengths[month - 1];
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Parse une saisie libre. `now` permet de figer « aujourd'hui » dans les tests.
DateTime? parseBirthDate(String raw, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());

  var s = _foldAccents(raw.trim().toLowerCase());
  if (s.isEmpty) return null;

  // Sépare les frontières chiffre/lettre : "17mai2000" -> "17 mai 2000".
  s = s.replaceAllMapped(
    RegExp(r'(?<=[0-9])(?=[a-z])|(?<=[a-z])(?=[0-9])'),
    (_) => ' ',
  );
  // Uniformise les séparateurs autorisés ( / - . espace ) en espace simple.
  s = s
      .replaceAll(RegExp(r'[/.\-]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  int? day;
  int? month;
  int? year;

  // Forme compacte sans séparateur : exactement JJMMYYYY.
  if (RegExp(r'^\d{8}$').hasMatch(s)) {
    day = int.parse(s.substring(0, 2));
    month = int.parse(s.substring(2, 4));
    year = int.parse(s.substring(4, 8));
  } else {
    final parts = s.split(' ');
    if (parts.length != 3) return null;

    day = int.tryParse(parts[0]);
    year = int.tryParse(parts[2]);
    if (parts[2].length != 4) return null; // année toujours sur 4 chiffres

    final rawMonth = parts[1];
    month = int.tryParse(rawMonth) ?? _monthsByName[rawMonth];
  }

  if (day == null || month == null || year == null) return null;
  if (month < 1 || month > 12) return null;
  if (year < 1900 || year > today.year) return null;
  if (day < 1 || day > _daysInMonth(month, year)) return null;

  final parsed = DateTime(year, month, day);
  // Garde-fou : DateTime réajuste silencieusement une date invalide.
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  if (parsed.isAfter(today)) return null; // pas de date future

  return parsed;
}

/// « 17 mai 2000 » — rendu lisible et accentué, pour la confirmation UI et le
/// préremplissage d'une valeur déjà connue.
String formatBirthDateFr(DateTime d) =>
    '${d.day} ${_frMonthLabels[d.month - 1]} ${d.year}';

/// Âge MINIMUM requis pour utiliser Auryel (décision produit J2).
///
/// SOURCE UNIQUE — ne jamais réécrire « 18 » ailleurs : importer cette
/// constante. La règle est appliquée à l'onboarding (saisie de la date) et à
/// toute édition ultérieure de la date de naissance ; elle N'EST PAS rejouée
/// sur la restauration d'une session déjà authentifiée (cf. rapport J2 §4).
const int kMinimumUserAge = 18;

/// Message neutre (non culpabilisant) affiché quand la personne a moins de
/// [kMinimumUserAge] ans. SOURCE UNIQUE du wording côté UI.
const String kMinimumAgeMessage =
    'Auryel est réservé aux personnes âgées de 18 ans ou plus.';

/// Âge révolu (années complètes) à la date [now] pour une naissance
/// [birthDate]. Calcul JOUR/MOIS/ANNÉE : l'anniversaire de l'année courante
/// doit être atteint pour compter l'année (pas un simple `annéeCourante -
/// annéeNaissance`). Une date dans le futur donne un âge négatif.
int computeAge(DateTime birthDate, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  final birth = _dateOnly(birthDate);
  var age = today.year - birth.year;
  final beforeBirthdayThisYear =
      today.month < birth.month ||
      (today.month == birth.month && today.day < birth.day);
  if (beforeBirthdayThisYear) age -= 1;
  return age;
}

/// `true` si [birthDate] correspond à un âge ≥ [kMinimumUserAge] à la date
/// [now]. Une date dans le futur ou trop récente -> `false` (refus propre,
/// jamais d'exception).
bool meetsMinimumAge(DateTime birthDate, {DateTime? now}) =>
    computeAge(birthDate, now: now) >= kMinimumUserAge;

/// `true` si [d] est une date de naissance EXPLOITABLE pour un contrôle d'âge :
/// non nulle, pas dans le futur, année ≥ 1900. Sert au GATE 18+ à distinguer
/// « date absente / malformée / incohérente » (⇒ demander une correction) de
/// « date valide mais mineure » (⇒ écran bloqué). Une date future n'est JAMAIS
/// traitée comme un âge (négatif) : elle est « non exploitable ».
bool isUsableBirthDate(DateTime? d, {DateTime? now}) {
  if (d == null) return false;
  final today = _dateOnly(now ?? DateTime.now());
  final birth = _dateOnly(d);
  return birth.year >= 1900 && !birth.isAfter(today);
}
