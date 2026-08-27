import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/widgets/advisors_carousel.dart';

void main() {
  test('les 10 conseillers ont une guideKey EXACTE (clé backend)', () {
    final byName = {for (final a in kAdvisors) a.name: a.guideKey};

    expect(byName, {
      'Séléna': 'selena',
      'Luna': 'luna',
      'Maïa': 'maia',
      'Théa': 'thea',
      'Cassandre': 'cassandre',
      'Myriam': 'myriam',
      'Orion': 'orion',
      'Ezra': 'ezra',
      'Kaël': 'kael',
      'Raphaël': 'raphael',
    });
  });

  test('guideKey : uniquement des minuscules ASCII (jamais un nom accentué), '
      'et 10 clés distinctes', () {
    final ascii = RegExp(r'^[a-z]+$');
    for (final a in kAdvisors) {
      expect(ascii.hasMatch(a.guideKey), isTrue,
          reason: '${a.name} -> ${a.guideKey}');
    }
    // Séléra/Maïa/Kaël/Théa/Raphaël ont des accents : la clé n'en a jamais.
    expect(advisorByNameOrNull('Séléna')!.guideKey, 'selena');
    expect(advisorByNameOrNull('Kaël')!.guideKey, 'kael');
    expect(advisorByNameOrNull('Théa')!.guideKey, 'thea');
    expect(kAdvisors.map((a) => a.guideKey).toSet().length, 10);
  });

  test('Maïa -> guideKey "maia" (jamais "Séléna" ni "selena")', () {
    final maia = advisorByNameOrNull('Maïa');
    expect(maia, isNotNull);
    expect(maia!.guideKey, 'maia');
  });

  test('advisorByNameOrNull : null si le nom est inconnu ou null', () {
    expect(advisorByNameOrNull('Inconnu'), isNull);
    expect(advisorByNameOrNull(null), isNull);
    expect(advisorByNameOrNull('selena'), isNull); // clé != nom affiché
    expect(advisorByNameOrNull('Séléna')?.guideKey, 'selena');
  });
}
