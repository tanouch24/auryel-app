import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/theme/auryel_theme.dart';

/// UX-B §18 — tests typographie : utiles, pas fragiles. On vérifie que la
/// famille est Inter partout et qu'AUCUNE police réseau n'est requise (fichiers
/// embarqués). On ne teste PAS des tailles en pixels.
void main() {
  test('AuryelText : toutes les fabriques rendent la famille Inter', () {
    expect(AuryelText.fontFamily, 'Inter');
    expect(AuryelText.body().fontFamily, 'Inter');
    expect(AuryelText.display().fontFamily, 'Inter');
    expect(AuryelText.screenTitle().fontFamily, 'Inter');
    expect(AuryelText.sectionTitle().fontFamily, 'Inter');
    expect(AuryelText.cardTitle().fontFamily, 'Inter');
    expect(AuryelText.bodyText().fontFamily, 'Inter');
    expect(AuryelText.bodySecondary().fontFamily, 'Inter');
    expect(AuryelText.button().fontFamily, 'Inter');
    expect(AuryelText.navLabel(color: const Color(0xFFFFFFFF)).fontFamily,
        'Inter');
    expect(AuryelText.overline().fontFamily, 'Inter');
  });

  test('le repli n\'est jamais un serif ni une ressource réseau', () {
    final fallback = AuryelText.fontFamilyFallback;
    expect(fallback, isNotEmpty);
    for (final f in fallback) {
      expect(f.toLowerCase().contains('http'), isFalse);
      expect(f.toLowerCase().contains('serif') && f.toLowerCase() != 'sans-serif',
          isFalse);
      expect(f.toLowerCase(), isNot(contains('cormorant')));
    }
  });

  test('ThemeData.dark : le TextTheme hérité utilise Inter', () {
    final theme = AuryelTheme.dark;
    for (final style in [
      theme.textTheme.bodyLarge,
      theme.textTheme.bodyMedium,
      theme.textTheme.titleLarge,
      theme.textTheme.labelLarge,
      theme.primaryTextTheme.bodyMedium,
    ]) {
      expect(style?.fontFamily, 'Inter');
    }
  });

  testWidgets('un écran sous AuryelTheme hérite bien de la famille Inter',
      (tester) async {
    late TextStyle resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: AuryelTheme.dark,
        home: Builder(
          builder: (context) {
            resolved = Theme.of(context).textTheme.bodyMedium!;
            return const Scaffold(body: Text('écran'));
          },
        ),
      ),
    );
    expect(resolved.fontFamily, 'Inter');
  });

  test('pubspec : Inter est déclarée en asset LOCAL (4 graisses), pas google_fonts',
      () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    // Famille déclarée.
    expect(pubspec, contains('family: Inter'));

    // Les 4 fichiers .ttf embarqués, chemins locaux (jamais d'URL).
    for (final file in const [
      'fonts/Inter/Inter-Regular.ttf',
      'fonts/Inter/Inter-Medium.ttf',
      'fonts/Inter/Inter-SemiBold.ttf',
      'fonts/Inter/Inter-Bold.ttf',
    ]) {
      expect(pubspec, contains(file), reason: '$file doit être déclaré');
      expect(File(file).existsSync(), isTrue, reason: '$file doit exister');
    }

    // Graisses 400 / 500 / 600 / 700.
    for (final w in const ['weight: 400', 'weight: 500', 'weight: 600', 'weight: 700']) {
      expect(pubspec, contains(w));
    }

    // Plus aucune dépendance à google_fonts (chargement réseau au runtime).
    expect(pubspec, isNot(contains('google_fonts')));
  });

  test('aucune référence à google_fonts / GoogleFonts dans lib/', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    final importRe = RegExp(r'''import\s+['"]package:google_fonts''');
    for (final f in dartFiles) {
      final src = f.readAsStringSync();
      expect(importRe.hasMatch(src), isFalse,
          reason: '${f.path} importe google_fonts');
      expect(src.contains('GoogleFonts.'), isFalse,
          reason: '${f.path} utilise GoogleFonts');
    }
  });
}
