import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/analytics/first_party_analytics.dart';
import 'package:auryel/api/api_client.dart';

void main() {
  test('analytics failure is swallowed and does not block the caller', () async {
    final api = ApiClient(
      baseUrl: 'http://test.local',
      httpClient: MockClient((_) async => throw TimeoutException('offline')),
    );
    final analytics = FirstPartyAnalytics(
      api: api,
      tokenProvider: () async => 'session-token',
    );

    await expectLater(analytics.log('app_opened'), completes);
  });

  test('session events are sent once and never include private content', () async {
    final bodies = <String>[];
    final api = ApiClient(
      baseUrl: 'http://test.local',
      httpClient: MockClient((request) async {
        bodies.add(request.body);
        return http.Response('{}', 202);
      }),
    );
    final analytics = FirstPartyAnalytics(
      api: api,
      tokenProvider: () async => 'session-token',
    );

    await analytics.logSessionStarted();
    await analytics.logSessionStarted();

    expect(bodies, hasLength(2));
    expect(bodies.join(), contains('app_opened'));
    expect(bodies.join(), contains('session_started'));
    expect(bodies.join(), isNot(contains('message')));
    expect(bodies.join(), isNot(contains('prompt')));
  });
}
