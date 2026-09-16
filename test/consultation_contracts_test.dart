import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/data/consultation.dart';

// ===========================================================================
// LOT CORRECTIF 1 — contrats consultation.
//   - ConsultationMessageDto / ConsultationMessageResponse : message_id +
//     llm_status, fail-safe (null si absent -> compat backend ancien).
//   - ApiClient : 403 -> ApiForbiddenException dédiée (jamais une panne
//     serveur générique). 401 / 402 / 404 / réseau inchangés.
// ===========================================================================

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

ConsultationApi _apiReturning(int status, Map<String, dynamic> body) =>
    ConsultationApi(
      ApiClient(
        httpClient: MockClient((_) async => _json(body, status)),
        baseUrl: 'http://test.local',
      ),
    );

void main() {
  group('ConsultationMessageDto — message_id / llm_status', () {
    test('1/2 — parse message_id + llm_status', () {
      final dto = ConsultationMessageDto.fromJson({
        'role': 'assistant',
        'content': 'salut',
        'timestamp': '2026-09-06T10:00:00Z',
        'message_id': 'm-42',
        'llm_status': 'ok',
      });
      expect(dto.messageId, 'm-42');
      expect(dto.llmStatus, 'ok');
      expect(dto.isUser, isFalse);
    });

    test('repli sur `id` si `message_id` absent', () {
      final dto = ConsultationMessageDto.fromJson({
        'role': 'assistant',
        'content': 'x',
        'id': 'm-7',
      });
      expect(dto.messageId, 'm-7');
    });

    test('5 — champs absents -> null, parsing toujours OK', () {
      final dto = ConsultationMessageDto.fromJson({
        'role': 'user',
        'content': 'coucou',
      });
      expect(dto.messageId, isNull);
      expect(dto.llmStatus, isNull);
      expect(dto.content, 'coucou');
    });

    test('valeurs vides / non-String -> null (fail-safe, aucune coercion)', () {
      final dto = ConsultationMessageDto.fromJson({
        'role': 'assistant',
        'content': 'x',
        'message_id': '',
        'llm_status': 123,
      });
      expect(dto.messageId, isNull);
      expect(dto.llmStatus, isNull);
    });
  });

  group('ConsultationMessageResponse — replyMessageId / llmStatus', () {
    Map<String, dynamic> base(Map<String, dynamic> extra) => {
      'reply': 'ma réponse',
      'consultation': null,
      'quota': null,
      ...extra,
    };

    test('3/4 — parse message_id + llm_status à la racine', () {
      final r = ConsultationMessageResponse.fromJson(
        base({'message_id': 'm-1', 'llm_status': 'ok'}),
      );
      expect(r.reply, 'ma réponse');
      expect(r.replyMessageId, 'm-1');
      expect(r.llmStatus, 'ok');
    });

    test('tolère la forme imbriquée `message: {id, llm_status}`', () {
      final r = ConsultationMessageResponse.fromJson(
        base({
          'message': {'id': 'm-9', 'llm_status': 'fallback'},
        }),
      );
      expect(r.replyMessageId, 'm-9');
      expect(r.llmStatus, 'fallback');
    });

    test('tolère `message: {message_id: ...}`', () {
      final r = ConsultationMessageResponse.fromJson(
        base({
          'message': {'message_id': 'm-3'},
        }),
      );
      expect(r.replyMessageId, 'm-3');
    });

    test(
      '5 — champs absents -> null (compat backend ancien), reply intact',
      () {
        final r = ConsultationMessageResponse.fromJson(base({}));
        expect(r.replyMessageId, isNull);
        expect(r.llmStatus, isNull);
        expect(r.reply, 'ma réponse');
      },
    );
  });

  group('ApiClient — mapping 403 (ApiForbiddenException)', () {
    test(
      '11 — 403 age_verification_required identifié (code + body)',
      () async {
        try {
          await _apiReturning(403, {
            'error': 'age_verification_required',
          }).sendMessage(bearer: 't', message: 'x');
          fail('devait lever');
        } on ApiForbiddenException catch (e) {
          expect(e.statusCode, 403);
          expect(e.code, 'age_verification_required');
          expect(e.body['error'], 'age_verification_required');
        }
      },
    );

    test('12 — 403 adult_required identifié', () async {
      try {
        await _apiReturning(403, {
          'error': 'adult_required',
        }).sendMessage(bearer: 't', message: 'x');
        fail('devait lever');
      } on ApiForbiddenException catch (e) {
        expect(e.code, 'adult_required');
      }
    });

    test('13 — un 403 n\'est jamais une ApiException générique nue', () async {
      try {
        await _apiReturning(403, {
          'error': 'adult_required',
        }).sendMessage(bearer: 't', message: 'x');
        fail('devait lever');
      } catch (e) {
        expect(e, isA<ApiForbiddenException>());
      }
    });

    test('14 — 401 / 402 / 404 / 5xx inchangés', () async {
      await expectLater(
        _apiReturning(401, {
          'error': 'x',
        }).sendMessage(bearer: 't', message: 'x'),
        throwsA(isA<ApiUnauthorizedException>()),
      );
      await expectLater(
        _apiReturning(402, {
          'error': 'consultation_credit_exhausted',
          'rewarded': {'questions_available': 2},
        }).sendMessage(bearer: 't', message: 'x'),
        throwsA(
          predicate(
            (e) =>
                e is ApiNoCreditException &&
                e.code == 'consultation_credit_exhausted' &&
                QuotaDto.fromJson(e.body['rewarded'] as Map<String, dynamic>)
                        .questionsAvailable ==
                    2,
          ),
        ),
      );
      await expectLater(
        _apiReturning(404, {
          'error': 'tirage_not_found',
        }).sendMessage(bearer: 't', message: 'x'),
        throwsA(
          predicate(
            (e) =>
                e is ApiException &&
                e is! ApiForbiddenException &&
                e.statusCode == 404,
          ),
        ),
      );
      await expectLater(
        _apiReturning(500, {
          'error': 'boom',
        }).sendMessage(bearer: 't', message: 'x'),
        throwsA(
          predicate((e) => e is ApiException && e is! ApiForbiddenException),
        ),
      );

      // Réseau : inchangé (ClientException -> ApiNetworkException).
      final netApi = ConsultationApi(
        ApiClient(
          httpClient: MockClient((_) async => throw http.ClientException('x')),
          baseUrl: 'http://test.local',
        ),
      );
      await expectLater(
        netApi.sendMessage(bearer: 't', message: 'x'),
        throwsA(isA<ApiNetworkException>()),
      );
    });
  });
}
