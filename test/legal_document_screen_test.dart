import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/config/legal_texts.dart';
import 'package:auryel/screens/legal_document_screen.dart';

void main() {
  Future<void> pump(
    WidgetTester t, {
    required String title,
    required String body,
  }) => t.pumpWidget(
    MaterialApp(
      home: LegalDocumentScreen(title: title, body: body),
    ),
  );

  testWidgets('affiche le titre et le corps, sans rien déclencher', (t) async {
    await pump(t, title: 'Mentions légales', body: kLegalNoticeInAppText);

    expect(find.text('Mentions légales'), findsOneWidget);
    expect(find.textContaining('3E Technology Ltd'), findsWidgets);
    expect(find.textContaining('company number 17179077'), findsWidgets);
    expect(find.textContaining('contact@auryelvoyance.com'), findsWidgets);
    // titre de section (ligne tout en capitales)
    expect(find.text('ÉDITEUR'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('bouton retour ferme l\'écran', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LegalDocumentScreen(
                      title: 'CGU',
                      body: kTermsInAppText,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byType(LegalDocumentScreen), findsOneWidget);

    await t.tap(find.byType(IconButton));
    await t.pumpAndSettle();
    expect(find.byType(LegalDocumentScreen), findsNothing);
  });

  testWidgets('rendu des 4 documents in-app sans exception', (t) async {
    for (final doc in <(String, String)>[
      ('Politique de confidentialité', kPrivacyPolicyInAppText),
      ('Conditions d’utilisation', kTermsInAppText),
      ('Conditions Auryel Premium', kPremiumTermsInAppText),
      ('Mentions légales', kLegalNoticeInAppText),
    ]) {
      await pump(t, title: doc.$1, body: doc.$2);
      await t.pump();
      expect(find.text(doc.$1), findsOneWidget);
      expect(t.takeException(), isNull);
    }
  });

  test('contenus juridiques : points essentiels présents', () {
    // Le retour à la ligne « dur » des constantes est neutralisé pour les
    // vérifications de fond.
    String flat(String s) => s.replaceAll('\n', ' ');

    // Disclaimer produit — wording canonique.
    expect(
      kAuryelDisclaimerText,
      contains('à titre indicatif et de divertissement'),
    );
    expect(kAuryelDisclaimerText, contains('professionnel de santé'));
    expect(kAiResponsesDisclaimerText, contains('inexactes ou incomplètes'));

    // Premium : nature non contractuelle des récompenses, fonctions V1 exclues.
    final premium = flat(kPremiumTermsInAppText);
    expect(premium, contains('8 heures de consultation par mois'));
    expect(premium, contains('le prix du magasin fait foi'));
    expect(premium, contains('ne sont pas disponibles à ce jour'));
    expect(premium, contains('bonus non contractuels'));

    // Confidentialité : installation_id non transmis ; notifications push +
    // mesure publicitaire Meta déclarées et sous consentement explicite.
    final privacy = flat(kPrivacyPolicyInAppText);
    expect(privacy, contains("il n'est pas transmis au serveur à ce jour"));
    expect(privacy, contains('Firebase Cloud Messaging'));
    expect(privacy, contains('Meta Platforms, Inc.'));
    expect(privacy, contains("n'est pas pré-coché et reste révocable"));
    expect(privacy,
        contains("Aucune mesure publicitaire sans votre consentement explicite"));
    expect(privacy,
        contains("identifiant publicitaire de l'appareil n'est pas collecté"));

    // Identité éditeur.
    expect(kPublisherIdentitySummary, contains('3E Technology Ltd'));
    expect(kPublisherIdentitySummary, contains('17179077'));
    expect(kPublisherIdentitySummary, contains('contact@auryelvoyance.com'));
  });
}
