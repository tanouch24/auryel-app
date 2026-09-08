import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/account_api.dart';
import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/installation_id_store.dart';
import 'package:auryel/data/local_user_data.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/state/auth_controller.dart';

// ===========================================================================
// LOT ANTI-ABUS HEURE GRATUITE — InstallationIdStore.
// Identifiant d'INSTALLATION aléatoire, stockage chiffré, conservé au
// logout / suppression de compte, aucun payload réseau modifié.
// ===========================================================================

const _hex32 = r'^[0-9a-f]{32}$';

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  // -------------------------------------------------------------------------
  // Génération / format / entropie
  // -------------------------------------------------------------------------
  group('generateInstallationId / isValidInstallationId', () {
    test('5 — 32 hex minuscules = 128 bits', () {
      final id = generateInstallationId(Random.secure());
      expect(id, matches(_hex32));
      expect(id.length, 32);
      expect(isValidInstallationId(id), isTrue);
    });

    test('1000 générations -> toutes valides et distinctes', () {
      final seen = <String>{};
      for (var i = 0; i < 1000; i++) {
        final id = generateInstallationId();
        expect(id, matches(_hex32));
        seen.add(id);
      }
      expect(seen.length, 1000);
    });

    test('7 — valeurs invalides rejetées', () {
      for (final bad in [
        null,
        '',
        '   ',
        'pas-hex',
        'ABCDEF0123456789ABCDEF0123456789', // majuscules
        '0123456789abcdef0123456789abcde', // 31
        '0123456789abcdef0123456789abcdef0', // 33
        'nina@example.com',
      ]) {
        expect(isValidInstallationId(bad), isFalse, reason: '$bad');
      }
    });

    test('8 — l\'id ne contient ni email ni prénom ni date', () {
      final id = generateInstallationId();
      expect(id.contains('@'), isFalse);
      expect(id.contains('nina'), isFalse);
      expect(id.contains('1994'), isFalse);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(id), isTrue); // hex pur
    });
  });

  // -------------------------------------------------------------------------
  // InMemoryInstallationIdStore — comportement getOrCreate
  // -------------------------------------------------------------------------
  group('InMemoryInstallationIdStore', () {
    test('1/2 — 1er appel génère, 2e appel renvoie le MÊME id', () async {
      final s = InMemoryInstallationIdStore();
      final a = await s.getOrCreate();
      final b = await s.getOrCreate();
      expect(a, matches(_hex32));
      expect(b, a);
    });

    test('3 — nouvelle instance sur le MÊME stockage -> même id', () async {
      final s1 = InMemoryInstallationIdStore();
      final id = await s1.getOrCreate();
      final s2 = InMemoryInstallationIdStore(stored: s1.stored);
      expect(await s2.getOrCreate(), id);
    });

    test('4 — deux stockages vierges -> ids différents', () async {
      final a = await InMemoryInstallationIdStore().getOrCreate();
      final b = await InMemoryInstallationIdStore().getOrCreate();
      expect(a, isNot(b));
    });

    test('6 — valeur vide stockée -> régénération', () async {
      final s = InMemoryInstallationIdStore(stored: '');
      final id = await s.getOrCreate();
      expect(id, matches(_hex32));
      expect(s.stored, id); // désormais persisté proprement
    });

    test('7 — valeur invalide stockée -> régénération', () async {
      final s = InMemoryInstallationIdStore(stored: 'CORROMPU!!');
      final id = await s.getOrCreate();
      expect(id, matches(_hex32));
    });

    test('E — écriture qui échoue : id valide pour la session, NON persisté, '
        'régénéré au « prochain lancement »', () async {
      final s1 = InMemoryInstallationIdStore(failWrites: true);
      final id1 = await s1.getOrCreate();
      expect(id1, matches(_hex32));
      expect(s1.persistedOk, isFalse);
      expect(s1.stored, isNull); // rien sur "disque"
      expect(await s1.getOrCreate(), id1); // stable dans la session (cache)

      // Nouveau "lancement" : stockage toujours vide -> nouvel id.
      final s2 = InMemoryInstallationIdStore(
        failWrites: true,
        stored: s1.stored,
      );
      expect(await s2.getOrCreate(), isNot(id1));
    });
  });

  // -------------------------------------------------------------------------
  // SecureInstallationIdStore — vraie classe, FlutterSecureStorage mocké
  // -------------------------------------------------------------------------
  group('SecureInstallationIdStore', () {
    test('10 — persiste puis relit : deux instances partageant le stockage '
        'chiffré renvoient le même id ; isPersisted == true', () async {
      final s1 = SecureInstallationIdStore();
      final id = await s1.getOrCreate();
      expect(id, matches(_hex32));
      expect(s1.isPersisted, isTrue);

      final s2 = SecureInstallationIdStore();
      expect(await s2.getOrCreate(), id);
      expect(s2.isPersisted, isTrue);
    });

    test('15 — clés distinctes : installation ≠ jeton de session', () {
      expect(kInstallationIdStorageKey, 'auryel_installation_id_v1');
      expect(SecureInstallationIdStore.storageKey, kInstallationIdStorageKey);
      expect(kInstallationIdStorageKey, isNot('auryel_session_token'));
    });
  });

  // -------------------------------------------------------------------------
  // Cycle de vie via AuthController
  // -------------------------------------------------------------------------
  group('Lifecycle — installation_id CONSERVÉ', () {
    AuthController build(
      Future<http.Response> Function(http.Request) handler, {
      required InstallationIdStore iid,
      String? token = 'tok',
    }) {
      final client = ApiClient(
        httpClient: MockClient(handler),
        baseUrl: 'http://test.local',
      );
      return AuthController(
        repository: AuthRepository(
          api: AuthApi(client),
          tokenStore: InMemoryTokenStore(token),
        ),
        profileApi: ProfileApi(client),
        consultationApi: ConsultationApi(client),
        tirageApi: TirageApi(client),
        accountApi: AccountApi(client),
        localUserData: LocalUserData(),
        installationIdStore: iid,
      );
    }

    test('9 — logout() ne change pas installation_id', () async {
      final iid = InMemoryInstallationIdStore();
      final c = build((_) async => _json({'status': 'ok'}), iid: iid);
      final before = await c.installationId();
      await c.logout();
      expect(await c.installationId(), before);
      expect(iid.stored, before); // toujours "sur disque"
    });

    test('10/11 — deleteAccount() 2xx purge le compte mais PAS '
        'installation_id ; clearPersonal() non plus', () async {
      SharedPreferences.setMockInitialValues({
        'auryel_onboarding_v1': '{"firstName":"Nina"}',
        'auryel.daily_mission.tirage': '2026-09-06',
      });
      final iid = InMemoryInstallationIdStore();
      final c = build((req) async {
        if (req.method == 'DELETE') return _json({'status': 'deleted'});
        return _json({}, 404);
      }, iid: iid);

      final before = await c.installationId();
      final out = await c.deleteAccount();
      expect(out, AccountDeletionOutcome.ok);

      // Compte purgé…
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auryel_onboarding_v1'), isNull);
      expect(await c.currentToken(), isNull);
      // …mais l'identifiant d'installation est CONSERVÉ.
      expect(await c.installationId(), before);
      expect(iid.stored, before);
    });

    test('12 — clearPersonal() ne supprimerait pas la clé installation même '
        'si elle était (à tort) dans SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        kInstallationIdStorageKey: '00112233445566778899aabbccddeeff',
        'auryel.daily_share.days': ['a'],
      });
      await LocalUserData().clearPersonal();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kInstallationIdStorageKey), isNotNull);
      expect(prefs.getStringList('auryel.daily_share.days'), isNull);
    });

    test(
      'AuthController sans store -> installationId() renvoie null',
      () async {
        final c = AuthController(
          repository: AuthRepository(
            api: AuthApi(
              ApiClient(
                httpClient: MockClient((_) async => _json({}, 404)),
                baseUrl: 'http://test.local',
              ),
            ),
            tokenStore: InMemoryTokenStore('tok'),
          ),
          profileApi: ProfileApi(
            ApiClient(
              httpClient: MockClient((_) async => _json({}, 404)),
              baseUrl: 'http://test.local',
            ),
          ),
          consultationApi: ConsultationApi(
            ApiClient(
              httpClient: MockClient((_) async => _json({}, 404)),
              baseUrl: 'http://test.local',
            ),
          ),
          tirageApi: TirageApi(
            ApiClient(
              httpClient: MockClient((_) async => _json({}, 404)),
              baseUrl: 'http://test.local',
            ),
          ),
        );
        expect(await c.installationId(), isNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  // 16 — AUCUN champ installation_id envoyé par register / login
  // -------------------------------------------------------------------------
  test(
    '16 — register/login n\'envoient PAS installation_id (contrat inchangé)',
    () async {
      final bodies = <String, Map<String, dynamic>>{};
      final client = ApiClient(
        httpClient: MockClient((req) async {
          if (req.method == 'POST' && req.body.isNotEmpty) {
            bodies[req.url.path] = jsonDecode(req.body) as Map<String, dynamic>;
          }
          if (req.url.path == '/api/account') {
            return _json({'user_id': 'A', 'email': 'nina@example.com'});
          }
          return _json({'token': 'tok-A'});
        }),
        baseUrl: 'http://test.local',
      );
      final auth = AuthController(
        repository: AuthRepository(
          api: AuthApi(client),
          tokenStore: InMemoryTokenStore(),
        ),
        profileApi: ProfileApi(client),
        consultationApi: ConsultationApi(client),
        tirageApi: TirageApi(client),
        installationIdStore: InMemoryInstallationIdStore(),
      );

      await auth.registerWithPassword('nina@example.com', 'motdepasse1');
      await auth.loginWithPassword('nina@example.com', 'motdepasse1');

      for (final path in ['/api/app/auth/register', '/api/app/auth/login']) {
        final b = bodies[path]!;
        expect(b.keys.toSet(), {'email', 'password'}, reason: path);
        expect(b.containsKey('installation_id'), isFalse);
        expect(b.containsKey('installationId'), isFalse);
        expect(b.containsKey('device_id'), isFalse);
      }
    },
  );

  // -------------------------------------------------------------------------
  // 17/18 — aucune permission AD_ID, aucun package de fingerprint appareil
  // -------------------------------------------------------------------------
  test(
    '17 — AndroidManifest : aucune permission publicitaire / adservices',
    () async {
      final manifest = await File('android/app/src/main/AndroidManifest.xml')
          .readAsString();
      expect(manifest.contains('AD_ID'), isFalse);
      expect(
        manifest.contains('com.google.android.gms.permission.AD_ID'),
        isFalse,
      );
      expect(manifest.toUpperCase().contains('ADSERVICES'), isFalse);
      expect(manifest.contains('READ_PHONE_STATE'), isFalse);
    },
  );

  test(
    '18 — pubspec : aucun package de fingerprint appareil / pub / tracking',
    () async {
      final pubspec = await File('pubspec.yaml').readAsString();
      for (final banned in [
        'device_info_plus',
        'device_info',
        'advertising_id',
        'app_tracking_transparency',
        'appsflyer',
        'adjust',
        'firebase_analytics',
        'sentry',
        'platform_device_id',
        'fingerprint',
      ]) {
        expect(pubspec.contains(banned), isFalse, reason: banned);
      }
    },
  );
}
