import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/birth_date_parser.dart';

void main() {
  // « Aujourd'hui » figé pour rendre le test « date future » déterministe.
  final now = DateTime(2026, 8, 31);
  DateTime? parse(String s) => parseBirthDate(s, now: now);

  group('formats acceptés -> 17 mai 2000', () {
    for (final input in [
      '17 mai 2000',
      '17052000',
      '17-05-2000',
      '17/05/2000',
      '17 05 2000',
      '17.05.2000',
      '17 MAI 2000',
      '  17   mai   2000  ',
      '17mai2000',
      '17 mai 2000',
    ]) {
      test('"$input"', () {
        expect(parse(input), DateTime(2000, 5, 17));
      });
    }
  });

  group('mois français, avec ou sans accents', () {
    test('17 février 2000', () => expect(parse('17 février 2000'), DateTime(2000, 2, 17)));
    test('17 fevrier 2000', () => expect(parse('17 fevrier 2000'), DateTime(2000, 2, 17)));
    test('3 août 2000', () => expect(parse('3 août 2000'), DateTime(2000, 8, 3)));
    test('3 aout 2000', () => expect(parse('3 aout 2000'), DateTime(2000, 8, 3)));
    test('1 décembre 1999', () => expect(parse('1 décembre 1999'), DateTime(1999, 12, 1)));
    test('1 decembre 1999', () => expect(parse('1 decembre 1999'), DateTime(1999, 12, 1)));
    test('25 JANVIER 1990', () => expect(parse('25 JANVIER 1990'), DateTime(1990, 1, 25)));
  });

  test('règle numérique JOUR/MOIS/ANNÉE : 05/06/2000 = 5 juin 2000', () {
    expect(parse('05/06/2000'), DateTime(2000, 6, 5));
  });

  group('années bissextiles', () {
    test('29/02/2000 -> valide (divisible par 400)', () {
      expect(parse('29/02/2000'), DateTime(2000, 2, 29));
    });
    test('29/02/2001 -> invalide', () => expect(parse('29/02/2001'), isNull));
    test('29/02/1900 -> invalide (divisible par 100, pas 400)', () {
      expect(parse('29/02/1900'), isNull);
    });
    test('29/02/2024 -> valide', () => expect(parse('29/02/2024'), DateTime(2024, 2, 29)));
  });

  group('dates impossibles -> null', () {
    test('31/02/2000', () => expect(parse('31/02/2000'), isNull));
    test('32/01/2000', () => expect(parse('32/01/2000'), isNull));
    test('00/01/2000', () => expect(parse('00/01/2000'), isNull));
    test('15/13/2000', () => expect(parse('15/13/2000'), isNull));
    test('15/00/2000', () => expect(parse('15/00/2000'), isNull));
    test('31/04/2000 (avril = 30 jours)', () => expect(parse('31/04/2000'), isNull));
  });

  group('date future -> null', () {
    test('01/01/2030', () => expect(parse('01/01/2030'), isNull));
    test('lendemain de now', () => expect(parse('01/09/2026'), isNull));
    test('now exactement -> accepté', () => expect(parse('31/08/2026'), DateTime(2026, 8, 31)));
  });

  group('saisies inexploitables -> null', () {
    test('vide', () => expect(parse(''), isNull));
    test('espaces', () => expect(parse('   '), isNull));
    test('texte libre', () => expect(parse('je ne sais plus'), isNull));
    test('année sur 2 chiffres', () => expect(parse('17/05/00'), isNull));
    test('mois inconnu', () => expect(parse('17 floreal 2000'), isNull));
    test('6 chiffres collés', () => expect(parse('170500'), isNull));
    test('année trop ancienne', () => expect(parse('17/05/1899'), isNull));
  });

  group('formatBirthDateFr', () {
    test('accentué', () {
      expect(formatBirthDateFr(DateTime(2000, 5, 17)), '17 mai 2000');
      expect(formatBirthDateFr(DateTime(1999, 8, 3)), '3 août 1999');
      expect(formatBirthDateFr(DateTime(2001, 12, 25)), '25 décembre 2001');
    });
    test('aller-retour parse -> format -> parse', () {
      final d = parse('17052000')!;
      expect(parse(formatBirthDateFr(d)), d);
    });
  });
}
