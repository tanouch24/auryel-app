import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/support_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/support_screen.dart';
import 'package:auryel/state/auth_controller.dart';

const _base = 'http://test.local';

http.Response _json(Map<String, dynamic> b, [int s = 200]) =>
    http.Response(jsonEncode(b), s, headers: {'content-type': 'application/json'});

class _Cap {
  int calls = 0;
  Map<String, dynamic>? body;
  String? authHeader;
  int status = 200;
  Object? throws;
  Duration delay = Duration.zero;
}

({SupportApi api, AuthController auth, _Cap cap}) _harness({String? token = 'tk'}) {
  final cap = _Cap();
  final client = ApiClient(
    baseUrl: _base,
    httpClient: MockClient((req) async {
      if (req.url.path == '/api/app/support' && req.method == 'POST') {
        cap.calls++;
        cap.authHeader = req.headers['Authorization'];
        cap.body = jsonDecode(req.body) as Map<String, dynamic>;
        if (cap.delay > Duration.zero) await Future<void>.delayed(cap.delay);
        if (cap.throws != null) throw cap.throws!;
        return _json({'status': 'sent'}, cap.status);
      }
      return _json({}, 404);
    }),
  );
  final auth = AuthController(
    repository: AuthRepository(
      api: AuthApi(client),
      tokenStore: InMemoryTokenStore(token),
    ),
    profileApi: ProfileApi(client),
    consultationApi: ConsultationApi(client),
    tirageApi: TirageApi(client),
  );
  return (api: SupportApi(client), auth: auth, cap: cap);
}

Widget _wrap(AuthController auth, SupportApi api) => AuthScope(
      controller: auth,
      child: MaterialApp(home: SupportScreen(apiOverride: api)),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('1/2 — écran visible, titre + champs', (t) async {
    final h = _harness();
    await t.pumpWidget(_wrap(h.auth, h.api));
    await t.pumpAndSettle();
    expect(find.text('Signaler un problème'), findsWidgets);
    expect(find.text('SUJET'), findsOneWidget);
    expect(find.text('DESCRIPTION'), findsOneWidget);
    expect(find.text('CATÉGORIE'), findsOneWidget);
    expect(find.text('Envoyer'), findsOneWidget);
  });

  testWidgets('3/4 — sujet et message requis (bouton désactivé)', (t) async {
    final h = _harness();
    await t.pumpWidget(_wrap(h.auth, h.api));
    await t.pumpAndSettle();
    // rien saisi -> tap sans effet
    await t.tap(find.text('Envoyer'));
    await t.pumpAndSettle();
    expect(h.cap.calls, 0);
    // sujet seul -> toujours pas
    await t.enterText(find.widgetWithText(TextField, 'Résume ton problème'), 's');
    await t.pump();
    await t.tap(find.text('Envoyer'));
    await t.pumpAndSettle();
    expect(h.cap.calls, 0);
    // + message -> OK
    await t.enterText(
        find.widgetWithText(TextField, 'Explique ce qui se passe'), 'm');
    await t.pump();
    await t.tap(find.text('Envoyer'));
    await t.pumpAndSettle();
    expect(h.cap.calls, 1);
  });

  testWidgets('6/7/8 — envoi : POST /api/app/support, catégorie, Bearer, '
      'métadonnées non sensibles', (t) async {
    final h = _harness();
    await t.pumpWidget(_wrap(h.auth, h.api));
    await t.pumpAndSettle();
    await t.enterText(
        find.widgetWithText(TextField, 'Résume ton problème'), '  Bug appli  ');
    await t.enterText(
        find.widgetWithText(TextField, 'Explique ce qui se passe'),
        'ça plante au démarrage');
    await t.pump();
    await t.tap(find.text('Envoyer'));
    await t.pumpAndSettle();

    expect(h.cap.calls, 1);
    expect(h.cap.authHeader, 'Bearer tk');
    expect(h.cap.body!['subject'], 'Bug appli'); // trimé
    expect(h.cap.body!['message'], 'ça plante au démarrage');
    expect(h.cap.body!['category'], 'account'); // 1re catégorie par défaut
    expect(h.cap.body!['platform'], isNotNull);
    expect(h.cap.body!['app_version'], isNotNull);
    // 12 — aucune donnée sensible
    for (final k in ['password', 'token', 'bearer', 'date_naissance',
        'birthDate', 'consultation', 'messages', 'email']) {
      expect(h.cap.body!.containsKey(k), isFalse, reason: k);
    }
  });

  testWidgets('9 — succès -> confirmation « Votre message a bien été envoyé »',
      (t) async {
    final h = _harness();
    await t.pumpWidget(_wrap(h.auth, h.api));
    await t.pumpAndSettle();
    await t.enterText(
        find.widgetWithText(TextField, 'Résume ton problème'), 's');
    await t.enterText(
        find.widgetWithText(TextField, 'Explique ce qui se passe'), 'm');
    await t.pump();
    await t.tap(find.text('Envoyer'));
    await t.pumpAndSettle();
    expect(find.text('Votre message a bien été envoyé.'), findsOneWidget);
    expect(find.text('Retour'), findsOneWidget);
  });

  testWidgets('10 — échec réseau -> message d’erreur, pas de fausse confirmation',
      (t) async {
    final h = _harness()..cap.throws = ApiException(503, code: 'support_unavailable');
    await t.pumpWidget(_wrap(h.auth, h.api));
    await t.pumpAndSettle();
    await t.enterText(
        find.widgetWithText(TextField, 'Résume ton problème'), 's');
    await t.enterText(
        find.widgetWithText(TextField, 'Explique ce qui se passe'), 'm');
    await t.pump();
    await t.tap(find.text('Envoyer'));
    await t.pumpAndSettle();
    expect(
      find.textContaining('Impossible d’envoyer votre message'),
      findsOneWidget,
    );
    expect(find.text('Votre message a bien été envoyé.'), findsNothing);
  });

  testWidgets('11 — double tap -> un seul envoi', (t) async {
    final h = _harness()..cap.delay = const Duration(milliseconds: 200);
    await t.pumpWidget(_wrap(h.auth, h.api));
    await t.pumpAndSettle();
    await t.enterText(
        find.widgetWithText(TextField, 'Résume ton problème'), 's');
    await t.enterText(
        find.widgetWithText(TextField, 'Explique ce qui se passe'), 'm');
    await t.pump();
    await t.tap(find.text('Envoi…').evaluate().isEmpty
        ? find.text('Envoyer')
        : find.text('Envoi…'));
    await t.pump(const Duration(milliseconds: 20));
    // 2e tap pendant l'envoi
    final btn = find.text('Envoi…');
    if (btn.evaluate().isNotEmpty) await t.tap(btn);
    await t.pumpAndSettle();
    expect(h.cap.calls, 1);
  });

  testWidgets('5/16 — longueurs limites : maxLength appliqué, pas d’overflow',
      (t) async {
    for (final w in const [360.0, 384.0, 430.0]) {
      final h = _harness();
      t.view.physicalSize = Size(w, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(_wrap(h.auth, h.api));
      await t.pumpAndSettle();
      await t.enterText(
          find.widgetWithText(TextField, 'Résume ton problème'), 'x' * 300);
      await t.pump();
      expect(t.takeException(), isNull, reason: '${w.toInt()} dp');
      final field = t.widget<TextField>(
          find.widgetWithText(TextField, 'Résume ton problème'));
      expect(field.maxLength, 140);
    }
  });
}
