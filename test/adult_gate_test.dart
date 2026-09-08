import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/account_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/adult_gate.dart';
import 'package:auryel/screens/onboarding/email_auth_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/widgets/main_nav_shell.dart';

const _base = 'http://test.local';
final DateTime _fixedNow = DateTime(2026, 9, 8);

http.Response _json(Map<String, dynamic> b, [int s = 200]) =>
    http.Response(jsonEncode(b), s, headers: {'content-type': 'application/json'});

class _NullRepo implements OnboardingRepository {
  @override
  Future<OnboardingRecord?> load() async => null;
  @override
  Future<void> save(OnboardingRecord record) async {}
  @override
  Future<void> clear() async {}
}

class _Harness {
  _Harness(this.auth, this.tokens, this.patchBodies, this.hits);
  final AuthController auth;
  final InMemoryTokenStore tokens;
  final List<Map<String, dynamic>> patchBodies;
  final List<String> hits;
}

/// [profiles] : file d'attente de réponses `GET /api/app/profile` — chaque
/// entrée est soit un Map (200), soit un int (status d'erreur), soit un
/// Exception (jetée). Consommée dans l'ordre ; la dernière est répétée.
_Harness _harness({
  required List<Object> profiles,
  String? token = 'tk',
  Duration profileDelay = Duration.zero,
}) {
  final hits = <String>[];
  final patchBodies = <Map<String, dynamic>>[];
  final tokens = InMemoryTokenStore(token);
  var idx = 0;
  final client = ApiClient(
    baseUrl: _base,
    httpClient: MockClient((req) async {
      hits.add('${req.method} ${req.url.path}');
      if (req.url.path == '/api/app/profile' && req.method == 'GET') {
        if (profileDelay > Duration.zero) await Future<void>.delayed(profileDelay);
        final entry = profiles[idx < profiles.length ? idx : profiles.length - 1];
        idx++;
        if (entry is int) return _json({'error': 'x'}, entry);
        if (entry is Exception) throw entry;
        return _json(entry as Map<String, dynamic>);
      }
      if (req.url.path == '/api/app/profile' && req.method == 'PATCH') {
        patchBodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return _json({
          'user_id': 'U',
          'guide': 'selena',
          'prenom': 'Ana',
          'date_naissance': (jsonDecode(req.body)
              as Map<String, dynamic>)['date_naissance'],
          'chemin_de_vie': '',
          'signe_zodiaque': '',
        });
      }
      if (req.url.path == '/api/app/account' && req.method == 'DELETE') {
        return _json({'status': 'deleted'});
      }
      return _json({}, 404);
    }),
  );
  final auth = AuthController(
    repository: AuthRepository(api: AuthApi(client), tokenStore: tokens),
    profileApi: ProfileApi(client),
    consultationApi: ConsultationApi(client),
    tirageApi: TirageApi(client),
    accountApi: AccountApi(client),
  );
  return _Harness(auth, tokens, patchBodies, hits);
}

AuryelState _state({DateTime? birthDate}) => AuryelState(
      repository: _NullRepo(),
      initial: OnboardingRecord(
        userId: 'U',
        selectedAdvisor: 'Séléna',
        firstName: 'Ana',
        birthDate: birthDate,
        portraitData: null,
        portraitFeedback: null,
        onboardingCompleted: true,
      ),
    );

Widget _wrap(_Harness h, AuryelState state) => AuthScope(
      controller: h.auth,
      child: AuryelStateScope(
        state: state,
        child: MaterialApp(home: AdultGate(clock: () => _fixedNow)),
      ),
    );

Map<String, dynamic> _profile({String? dob}) => {
      'user_id': 'U',
      'guide': 'selena',
      'prenom': 'Ana',
      'date_naissance': dob,
      'chemin_de_vie': '',
      'signe_zodiaque': '',
    };

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 2. session restaurée adulte (DOB locale) -> MainNavShell, SANS réseau
  testWidgets('2 — DOB locale adulte -> MainNavShell, aucun GET profile',
      (t) async {
    final h = _harness(profiles: [_profile(dob: '1990-01-01')]);
    await t.pumpWidget(_wrap(h, _state(birthDate: DateTime(1990, 1, 1))));
    await t.pumpAndSettle();
    expect(find.byType(MainNavShell), findsOneWidget);
    expect(h.hits.where((x) => x.contains('/api/app/profile')), isEmpty);
  });

  // 18. aucun flash du MainNavShell avant validation : la 1re frame est le
  //     spinner de vérification, jamais le shell.
  testWidgets('18 — aucun flash de MainNavShell pendant la vérification',
      (t) async {
    final h = _harness(
      profiles: [_profile(dob: '1990-01-01')],
      profileDelay: const Duration(milliseconds: 200),
    );
    await t.pumpWidget(_wrap(h, _state(birthDate: null)));
    // Pendant toute la fenêtre de vérification serveur : jamais MainNavShell.
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(milliseconds: 40));
      expect(find.byType(MainNavShell), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    }
    await t.pumpAndSettle();
    expect(find.byType(MainNavShell), findsOneWidget);
  });

  // 3/4. DOB absente / vide -> écran Vérification de l'âge
  testWidgets('3/4 — DOB serveur absente -> écran Vérification de l’âge',
      (t) async {
    final h = _harness(profiles: [_profile(dob: null)]);
    await t.pumpWidget(_wrap(h, _state(birthDate: null)));
    await t.pumpAndSettle();
    expect(find.text('Vérification de l’âge'), findsOneWidget);
    expect(find.byType(MainNavShell), findsNothing);
  });

  // 5. DOB serveur malformée -> écran Vérification
  testWidgets('5 — DOB serveur non ISO -> écran Vérification', (t) async {
    final h = _harness(profiles: [_profile(dob: '15/07/1994')]);
    await t.pumpWidget(_wrap(h, _state(birthDate: null)));
    await t.pumpAndSettle();
    expect(find.text('Vérification de l’âge'), findsOneWidget);
    expect(find.byType(MainNavShell), findsNothing);
  });

  // 6. DOB future -> traitée comme non exploitable -> écran Vérification
  testWidgets('6 — DOB serveur future -> écran Vérification (jamais « adulte »)',
      (t) async {
    final future = _iso(DateTime(_fixedNow.year + 1, 1, 1));
    final h = _harness(profiles: [_profile(dob: future)]);
    await t.pumpWidget(_wrap(h, _state(birthDate: null)));
    await t.pumpAndSettle();
    expect(find.text('Vérification de l’âge'), findsOneWidget);
    expect(find.byType(MainNavShell), findsNothing);
  });

  // 7. 17 ans 364 jours -> écran bloqué mineur
  testWidgets('7 — 17 ans 364 jours -> écran mineur bloqué', (t) async {
    final dob = _iso(DateTime(_fixedNow.year - 18, _fixedNow.month,
        _fixedNow.day + 1));
    final h = _harness(profiles: [_profile(dob: dob)]);
    await t.pumpWidget(_wrap(h, _state(birthDate: null)));
    await t.pumpAndSettle();
    expect(find.text('Accès réservé aux adultes'), findsOneWidget);
    expect(find.byType(MainNavShell), findsNothing);
  });

  // 8. exactement 18 ans aujourd'hui -> accepté
  testWidgets('8 — 18 ans pile aujourd’hui -> MainNavShell', (t) async {
    final dob = _iso(DateTime(_fixedNow.year - 18, _fixedNow.month,
        _fixedNow.day));
    final h = _harness(profiles: [_profile(dob: dob)]);
    await t.pumpWidget(_wrap(h, _state(birthDate: null)));
    await t.pumpAndSettle();
    expect(find.byType(MainNavShell), findsOneWidget);
  });

  // 9. 18 ans + 1 jour -> accepté
  testWidgets('9 — 18 ans et 1 jour -> MainNavShell', (t) async {
    final dob = _iso(DateTime(_fixedNow.year - 18, _fixedNow.month,
        _fixedNow.day - 1));
    final h = _harness(profiles: [_profile(dob: dob)]);
    await t.pumpWidget(_wrap(h, _state(birthDate: null)));
    await t.pumpAndSettle();
    expect(find.byType(MainNavShell), findsOneWidget);
  });

  // 10. mineur -> écran bloqué
  testWidgets('10 — mineur (14 ans) -> écran bloqué, jamais MainNavShell',
      (t) async {
    final h = _harness(profiles: [_profile(dob: _iso(DateTime(_fixedNow.year - 14, 1, 1)))]);
    await t.pumpWidget(_wrap(h, _state(birthDate: null)));
    await t.pumpAndSettle();
    expect(find.text('Accès réservé aux adultes'), findsOneWidget);
    expect(find.text('Se déconnecter'), findsOneWidget);
    expect(find.byType(MainNavShell), findsNothing);
  });

  // 11. retour Android ne contourne pas l'écran mineur
  testWidgets('11 — bouton retour ne ferme pas l’écran mineur', (t) async {
    final h = _harness(profiles: [_profile(dob: _iso(DateTime(_fixedNow.year - 14, 1, 1)))]);
    await t.pumpWidget(_wrap(h, _state(birthDate: null)));
    await t.pumpAndSettle();
    // Simule un appui « retour » système.
    final popped = await t.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(
        const MethodCall('popRoute'),
      ),
      (_) {},
    );
    await t.pumpAndSettle();
    expect(find.text('Accès réservé aux adultes'), findsOneWidget);
    expect(find.byType(MainNavShell), findsNothing);
    expect(popped, isNotNull);
  });

  // 12. profil API erreur -> écran d'erreur, jamais MainNavShell (FAIL CLOSED)
  testWidgets('12 — GET profile 503 -> écran d’erreur, pas de MainNavShell',
      (t) async {
    final h = _harness(profiles: [503]);
    await t.pumpWidget(_wrap(h, _state(birthDate: null)));
    await t.pumpAndSettle();
    expect(find.text('Vérification impossible'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.byType(MainNavShell), findsNothing);
  });

  // 13. retry profil fonctionne
  testWidgets('13 — « Réessayer » après une erreur -> succès -> MainNavShell',
      (t) async {
    final h = _harness(profiles: [503, _profile(dob: '1990-01-01')]);
    await t.pumpWidget(_wrap(h, _state(birthDate: null)));
    await t.pumpAndSettle();
    expect(find.text('Réessayer'), findsOneWidget);
    await t.tap(find.text('Réessayer'));
    await t.pumpAndSettle();
    expect(find.byType(MainNavShell), findsOneWidget);
  });

  // 14. logout depuis l'écran bloqué
  testWidgets('14 — « Se déconnecter » depuis l’écran mineur -> EmailAuthScreen',
      (t) async {
    final h = _harness(profiles: [_profile(dob: _iso(DateTime(_fixedNow.year - 14, 1, 1)))]);
    await t.pumpWidget(_wrap(h, _state(birthDate: null)));
    await t.pumpAndSettle();
    await t.tap(find.text('Se déconnecter'));
    await t.pumpAndSettle();
    expect(find.byType(EmailAuthScreen), findsOneWidget);
    expect(await h.tokens.read(), isNull);
  });

  // 15. DOB corrigée adulte -> accès
  testWidgets('15 — saisie d’une DOB adulte -> PATCH -> MainNavShell', (t) async {
    final h = _harness(profiles: [
      _profile(dob: null), // 1er GET : absente -> needsDob
      _profile(dob: '1994-01-01'), // GET post-PATCH : adulte
    ]);
    await t.pumpWidget(_wrap(h, _state(birthDate: null)));
    await t.pumpAndSettle();
    expect(find.text('Vérification de l’âge'), findsOneWidget);

    await t.enterText(find.byType(TextField), '01/01/1994');
    await t.pump();
    await t.tap(find.text('Continuer'));
    await t.pumpAndSettle();

    expect(h.patchBodies.single['date_naissance'], '1994-01-01');
    expect(find.byType(MainNavShell), findsOneWidget);
  });

  // 16. DOB corrigée mineure -> reste bloqué (aucun PATCH)
  testWidgets('16 — saisie d’une DOB mineure -> écran bloqué, aucun PATCH',
      (t) async {
    final h = _harness(profiles: [_profile(dob: null)]);
    await t.pumpWidget(_wrap(h, _state(birthDate: null)));
    await t.pumpAndSettle();

    final minorYear = _fixedNow.year - 15;
    await t.enterText(find.byType(TextField), '01/01/$minorYear');
    await t.pump();
    // Le bouton « Continuer » est désactivé pour une date mineure : on force
    // la validation par la touche de soumission.
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();

    expect(find.text('Accès réservé aux adultes'), findsOneWidget);
    expect(h.patchBodies, isEmpty);
    expect(find.byType(MainNavShell), findsNothing);
  });

  // 1. cas dégénéré : AdultGate sans token (ne se produit pas en vrai — le
  //    splash route vers EmailAuthScreen AVANT le gate). Ici on vérifie
  //    seulement le FAIL CLOSED : jamais MainNavShell sur une supposition.
  testWidgets('1 — aucun token -> FAIL CLOSED, jamais MainNavShell', (t) async {
    final h = _harness(profiles: [_profile(dob: null)], token: null);
    await t.pumpWidget(_wrap(h, _state(birthDate: null)));
    await t.pumpAndSettle();
    expect(find.byType(MainNavShell), findsNothing);
    expect(find.text('Vérification impossible'), findsOneWidget);
  });

  // 17. changement de compte -> recalcul : DOB locale d'un autre âge n'est
  //     PAS réutilisée si le serveur donne une autre valeur.
  testWidgets('17 — le serveur fait autorité quand la DOB locale est absente',
      (t) async {
    final h = _harness(profiles: [_profile(dob: _iso(DateTime(_fixedNow.year - 16, 1, 1)))]);
    await t.pumpWidget(_wrap(h, _state(birthDate: null)));
    await t.pumpAndSettle();
    expect(find.text('Accès réservé aux adultes'), findsOneWidget);
  });
}
