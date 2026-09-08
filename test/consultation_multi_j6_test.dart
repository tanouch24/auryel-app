import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/consultation.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';

// ===========================================================================
// J6-F1 — DTO / ConsultationApi / ConsultationController : multi-consultations.
// ===========================================================================

const _base = 'http://test.local';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _summary({
  String id = 'c-ezra',
  String advisorId = 'ezra',
  String? startedAt = '2026-09-01T10:00:00Z',
  String? lastActivityAt = '2026-09-01T10:05:00Z',
  bool windowActive = true,
  Object? preview = 'dernier message',
}) => {
  'id': id,
  'advisor_id': advisorId,
  'started_at': ?startedAt,
  'last_activity_at': ?lastActivityAt,
  'window_active': windowActive,
  'preview': ?preview,
};

Map<String, dynamic> _openBody({
  String id = 'c-ezra',
  String advisorId = 'ezra',
  bool openedNow = true,
}) => {
  'consultation': {
    'id': id,
    'advisor_id': advisorId,
    'started_at': '2026-09-01T10:00:00Z',
    'expires_at': '2026-09-01T12:00:00Z',
    'credit_source': 'time',
    'opened_now': openedNow,
  },
};

Map<String, dynamic> _stateBody() => {
  'consultation': {
    'id': 'c-1',
    'advisor_id': 'maia',
    'started_at': '2026-09-01T09:55:00Z',
    'expires_at': '2026-09-01T11:55:00Z',
    'seconds_remaining': 32400,
    'credit_source': 'time',
    'opened_now': false,
  },
  'time': {
    'first_free_remaining_seconds': 0,
    'premium_remaining_seconds': 28800,
    'purchased_remaining_seconds': 0,
    'total_remaining_seconds': 28800,
    'window_active': false,
    'window_expires_at': null,
  },
  'quota': {
    'is_premium': true,
    'monthly_limit': 8,
    'monthly_used': 1,
    'monthly_remaining': 7,
    'earned_available': 0,
    'first_free_available': false,
    'period_start': '2026-09-01T00:00:00Z',
    'period_end': '2026-10-01T00:00:00Z',
  },
};

typedef _ApiRig = ({ConsultationApi api, List<http.Request> reqs});

_ApiRig _apiRig(Future<http.Response> Function(http.Request req) handler) {
  final reqs = <http.Request>[];
  final client = ApiClient(
    httpClient: MockClient((req) async {
      reqs.add(req);
      return handler(req);
    }),
    baseUrl: _base,
  );
  return (api: ConsultationApi(client), reqs: reqs);
}

typedef _CtrlRig = ({
  ConsultationController controller,
  List<http.Request> reqs,
  InMemoryTokenStore tokens,
});

_CtrlRig _ctrlRig(
  Future<http.Response> Function(http.Request req) handler, {
  String? token = 'tok',
}) {
  final reqs = <http.Request>[];
  final tokens = InMemoryTokenStore(token);
  final client = ApiClient(
    httpClient: MockClient((req) async {
      reqs.add(req);
      return handler(req);
    }),
    baseUrl: _base,
  );
  final capi = ConsultationApi(client);
  final auth = AuthController(
    repository: AuthRepository(api: AuthApi(client), tokenStore: tokens),
    profileApi: ProfileApi(client),
    consultationApi: capi,
    tirageApi: TirageApi(client),
  );
  final controller = ConsultationController(api: capi, auth: auth);
  addTearDown(controller.dispose);
  return (controller: controller, reqs: reqs, tokens: tokens);
}

List<String> _paths(List<http.Request> reqs) =>
    reqs.map((r) => '${r.method} ${r.url.path}').toList();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // =========================================================================
  // A — DTO : ConsultationSummaryDto
  // =========================================================================
  group('DTO ConsultationSummaryDto', () {
    test('1 parse summary complet', () {
      final d = ConsultationSummaryDto.tryFromJson(_summary())!;
      expect(d.id, 'c-ezra');
      expect(d.advisorId, 'ezra');
      expect(d.startedAt, DateTime.utc(2026, 9, 1, 10, 0, 0));
      expect(d.lastActivityAt, DateTime.utc(2026, 9, 1, 10, 5, 0));
      expect(d.windowActive, isTrue);
      expect(d.preview, 'dernier message');
    });

    test('2 preview null / vide -> null, aucun crash', () {
      final noPreview = ConsultationSummaryDto.tryFromJson(
        _summary(preview: null),
      )!;
      expect(noPreview.preview, isNull);
      final emptyPreview = ConsultationSummaryDto.tryFromJson(
        _summary(preview: ''),
      )!;
      expect(emptyPreview.preview, isNull);
      final nonString = ConsultationSummaryDto.tryFromJson(
        _summary(preview: 42),
      )!;
      expect(nonString.preview, isNull);
    });

    test('3 last_activity_at absent / invalide -> null', () {
      expect(
        ConsultationSummaryDto.tryFromJson(_summary(lastActivityAt: null))!
            .lastActivityAt,
        isNull,
      );
      expect(
        ConsultationSummaryDto.tryFromJson(
          _summary(lastActivityAt: 'pas-une-date'),
        )!.lastActivityAt,
        isNull,
      );
      expect(
        ConsultationSummaryDto.tryFromJson(_summary(startedAt: null))!
            .startedAt,
        isNull,
      );
    });

    test('4 window_active true / false / absent', () {
      expect(
        ConsultationSummaryDto.tryFromJson(_summary(windowActive: true))!
            .windowActive,
        isTrue,
      );
      expect(
        ConsultationSummaryDto.tryFromJson(_summary(windowActive: false))!
            .windowActive,
        isFalse,
      );
      expect(
        ConsultationSummaryDto.tryFromJson({'id': 'x', 'advisor_id': 'ezra'})!
            .windowActive,
        isFalse,
      );
    });

    test('5 entrée inexploitable -> null ; listFromJson filtre / tolère', () {
      expect(ConsultationSummaryDto.tryFromJson(null), isNull);
      expect(ConsultationSummaryDto.tryFromJson('nope'), isNull);
      expect(
        ConsultationSummaryDto.tryFromJson({'advisor_id': 'ezra'}),
        isNull,
      ); // id manquant
      expect(
        ConsultationSummaryDto.tryFromJson({'id': 'c-1'}),
        isNull,
      ); // advisor_id manquant
      expect(ConsultationSummaryDto.listFromJson({}), isEmpty);
      expect(
        ConsultationSummaryDto.listFromJson({'consultations': 'pas-une-liste'}),
        isEmpty,
      );
      final mixed = ConsultationSummaryDto.listFromJson({
        'consultations': [
          _summary(id: 'c-ezra', advisorId: 'ezra'),
          {'advisor_id': 'luna'}, // sans id -> ignorée
          'garbage', // -> ignorée
          _summary(id: 'c-selena', advisorId: 'selena'),
        ],
      });
      expect(mixed.map((c) => c.advisorId), ['ezra', 'selena']);
    });
  });

  // =========================================================================
  // B — ConsultationApi
  // =========================================================================
  group('ConsultationApi', () {
    test('6 listConsultations -> GET /api/consultation/list', () async {
      final rig = _apiRig(
        (req) async => _json({
          'consultations': [_summary()],
        }),
      );
      await rig.api.listConsultations(bearer: 'tok');
      expect(_paths(rig.reqs), ['GET /api/consultation/list']);
      expect(rig.reqs.single.headers['Authorization'], 'Bearer tok');
    });

    test('7 listConsultations parse plusieurs fils', () async {
      final rig = _apiRig(
        (req) async => _json({
          'consultations': [
            _summary(id: 'c-ezra', advisorId: 'ezra'),
            _summary(id: 'c-selena', advisorId: 'selena', windowActive: false),
          ],
        }),
      );
      final list = await rig.api.listConsultations(bearer: 'tok');
      expect(list, hasLength(2));
      expect(list.map((c) => c.advisorId), ['ezra', 'selena']);
      expect(list[1].windowActive, isFalse);
    });

    test('8/9 openConsultation -> POST /api/consultation/open, body advisor_id '
        'exact', () async {
      final rig = _apiRig((req) async => _json(_openBody()));
      final dto = await rig.api.openConsultation(
        bearer: 'tok',
        advisorId: 'ezra',
      );
      expect(_paths(rig.reqs), ['POST /api/consultation/open']);
      expect(jsonDecode(rig.reqs.single.body), {'advisor_id': 'ezra'});
      expect(dto.advisorId, 'ezra');
      expect(dto.openedNow, isTrue);
    });

    test(
      '10 getMessages ciblé encode consultation_id ; sans -> pas de query',
      () async {
        final rig = _apiRig(
          (req) async => _json({'consultation_id': 'c-ezra', 'messages': []}),
        );
        await rig.api.getMessages(bearer: 'tok', consultationId: 'c-ezra');
        await rig.api.getMessages(bearer: 'tok');
        expect(rig.reqs[0].url.queryParameters['consultation_id'], 'c-ezra');
        expect(rig.reqs[0].url.path, '/api/consultation/messages');
        expect(rig.reqs[1].url.query, isEmpty);
      },
    );

    test(
      '11/12 sendMessage : consultation_id + tirage_id optionnels',
      () async {
        final rig = _apiRig(
          (req) async => _json({
            'reply': 'ok',
            'consultation': _openBody()['consultation'],
            'quota': _stateBody()['quota'],
            'time': _stateBody()['time'],
          }),
        );
        await rig.api.sendMessage(
          bearer: 'tok',
          message: 'salut',
          consultationId: 'c-ezra',
          tirageId: 't-1',
        );
        await rig.api.sendMessage(bearer: 'tok', message: 'salut2');
        final b0 = jsonDecode(rig.reqs[0].body) as Map<String, dynamic>;
        expect(b0['message'], 'salut');
        expect(b0['consultation_id'], 'c-ezra');
        expect(b0['tirage_id'], 't-1');
        final b1 = jsonDecode(rig.reqs[1].body) as Map<String, dynamic>;
        expect(b1, {'message': 'salut2'}); // legacy strict : rien d'autre
      },
    );

    test('13 aucun conseiller de profil injecté dans les bodies', () async {
      final rig = _apiRig((req) async {
        if (req.url.path == '/api/consultation/open') return _json(_openBody());
        return _json({
          'reply': 'r',
          'consultation': _openBody()['consultation'],
          'quota': _stateBody()['quota'],
        });
      });
      await rig.api.openConsultation(bearer: 'tok', advisorId: 'ezra');
      await rig.api.sendMessage(
        bearer: 'tok',
        message: 'x',
        consultationId: 'c-ezra',
      );
      final openBody = jsonDecode(rig.reqs[0].body) as Map<String, dynamic>;
      expect(openBody.keys, ['advisor_id']);
      final msgBody = jsonDecode(rig.reqs[1].body) as Map<String, dynamic>;
      expect(msgBody.keys.toSet(), {'message', 'consultation_id'});
      expect(msgBody.containsKey('guide'), isFalse);
      expect(msgBody.containsKey('advisor'), isFalse);
      expect(msgBody.containsKey('advisor_id'), isFalse);
    });
  });

  // =========================================================================
  // C — ConsultationController
  // =========================================================================
  group('ConsultationController', () {
    test('14 refreshConsultations remplit la liste', () async {
      final rig = _ctrlRig(
        (req) async => _json({
          'consultations': [
            _summary(id: 'c-ezra', advisorId: 'ezra'),
            _summary(id: 'c-selena', advisorId: 'selena'),
          ],
        }),
      );
      expect(rig.controller.hasConsultations, isFalse);
      await rig.controller.refreshConsultations();
      expect(rig.controller.consultations.map((c) => c.advisorId), [
        'ezra',
        'selena',
      ]);
      expect(rig.controller.hasConsultations, isTrue);
      expect(rig.controller.consultationsError, isNull);
    });

    test('15 liste vide supportée', () async {
      final rig = _ctrlRig((req) async => _json({'consultations': []}));
      await rig.controller.refreshConsultations();
      expect(rig.controller.consultations, isEmpty);
      expect(rig.controller.hasConsultations, isFalse);
    });

    test(
      '16 échec réseau -> ancienne liste conservée + error, aucun logout',
      () async {
        var call = 0;
        final rig = _ctrlRig((req) async {
          call++;
          if (call == 1) {
            return _json({
              'consultations': [
                _summary(id: 'c-ezra', advisorId: 'ezra'),
                _summary(id: 'c-selena', advisorId: 'selena'),
              ],
            });
          }
          return _json({'error': 'server'}, 500);
        });
        await rig.controller.refreshConsultations();
        expect(rig.controller.consultations, hasLength(2));
        await rig.controller.refreshConsultations();
        expect(rig.controller.consultations, hasLength(2)); // conservée
        expect(rig.controller.consultationsError, isNotNull);
        expect(await rig.tokens.read(), 'tok'); // pas de purge de session
      },
    );

    test('16b un /list en 401 ne déconnecte pas', () async {
      final rig = _ctrlRig(
        (req) async => _json({'error': 'unauthorized'}, 401),
      );
      await rig.controller.refreshConsultations();
      expect(
        rig.controller.consultationsError,
        isA<ApiUnauthorizedException>(),
      );
      expect(await rig.tokens.read(), 'tok');
    });

    test('17/18/19 openAdvisor : retourne le bon DTO, rafraîchit la liste, '
        'aucun PATCH profil', () async {
      final rig = _ctrlRig((req) async {
        if (req.url.path == '/api/consultation/open') {
          expect(jsonDecode(req.body), {'advisor_id': 'ezra'});
          return _json(_openBody(id: 'c-ezra', advisorId: 'ezra'));
        }
        if (req.url.path == '/api/consultation/list') {
          return _json({
            'consultations': [_summary(id: 'c-ezra', advisorId: 'ezra')],
          });
        }
        return _json({'error': 'unexpected ${req.url.path}'}, 404);
      });
      final dto = await rig.controller.openAdvisor('ezra');
      expect(dto.advisorId, 'ezra'); // 17
      expect(rig.controller.consultations.map((c) => c.advisorId), [
        'ezra',
      ]); // 18
      expect(_paths(rig.reqs), [
        'POST /api/consultation/open',
        'GET /api/consultation/list',
      ]);
      expect(
        rig.reqs.any((r) => r.url.path.contains('profile')),
        isFalse,
      ); // 19 : aucun PATCH /api/app/profile
    });

    test('20 deux conseillers coexistent dans consultations', () async {
      final rig = _ctrlRig(
        (req) async => _json({
          'consultations': [
            _summary(id: 'c-ezra', advisorId: 'ezra', windowActive: true),
            _summary(id: 'c-selena', advisorId: 'selena', windowActive: false),
          ],
        }),
      );
      await rig.controller.refreshConsultations();
      final byAdv = {
        for (final c in rig.controller.consultations) c.advisorId: c,
      };
      expect(byAdv.keys, containsAll(['ezra', 'selena']));
      expect(byAdv['ezra']!.windowActive, isTrue);
      expect(byAdv['selena']!.windowActive, isFalse);
    });

    test(
      '21 wallet/time legacy non régressé ; refresh() ne touche PAS /list',
      () async {
        final rig = _ctrlRig((req) async {
          if (req.url.path == '/api/consultation/state') {
            return _json(_stateBody());
          }
          return _json({'error': 'unexpected ${req.url.path}'}, 404);
        });
        await rig.controller.refresh();
        expect(rig.controller.active?.id, 'c-1');
        expect(rig.controller.time?.totalRemainingSeconds, 28800);
        expect(rig.controller.quota?.isPremium, isTrue);
        expect(_paths(rig.reqs), ['GET /api/consultation/state']);
        expect(rig.controller.consultations, isEmpty); // /list non appelé
      },
    );

    test(
      '22 refreshAll : /state + /list ; un /list KO ne casse pas /state',
      () async {
        final rig = _ctrlRig((req) async {
          if (req.url.path == '/api/consultation/state') {
            return _json(_stateBody());
          }
          if (req.url.path == '/api/consultation/list') {
            return _json({'error': 'down'}, 503);
          }
          return _json({'error': 'unexpected'}, 404);
        });
        await rig.controller.refreshAll();
        expect(_paths(rig.reqs), [
          'GET /api/consultation/state',
          'GET /api/consultation/list',
        ]);
        expect(rig.controller.active?.id, 'c-1'); // /state OK malgré /list KO
        expect(rig.controller.time?.totalRemainingSeconds, 28800);
        expect(rig.controller.consultationsError, isNotNull);
      },
    );

    test('23 aucun id de consultation persisté localement', () async {
      final rig = _ctrlRig((req) async {
        if (req.url.path == '/api/consultation/open') {
          return _json(_openBody(id: 'c-ezra', advisorId: 'ezra'));
        }
        return _json({
          'consultations': [_summary(id: 'c-ezra', advisorId: 'ezra')],
        });
      });
      await rig.controller.openAdvisor('ezra');
      await rig.controller.refreshConsultations();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });
  });
}
