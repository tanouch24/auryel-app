import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/unread_api.dart';
import 'package:auryel/services/app_update_alert.dart';
import 'package:auryel/services/launcher_badge_channel.dart';
import 'package:auryel/state/unread_controller.dart';

class _RecordingBadge implements LauncherBadgeChannel {
  final calls = <int>[];

  @override
  Future<void> sync(int count) async => calls.add(count);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'badge follows the server unread count, including clear and multiple',
    () async {
      var count = 0;
      final api = UnreadApi(
        ApiClient(
          baseUrl: 'http://test.local',
          httpClient: MockClient((request) async {
            if (request.url.path == '/api/app/unread') {
              return http.Response(
                jsonEncode({
                  'counts': {'consultation': count},
                }),
                200,
              );
            }
            if (request.url.path == '/api/app/unread/read') {
              count = 0;
              return http.Response('{}', 200);
            }
            return http.Response('{}', 404);
          }),
        ),
      );
      final badge = _RecordingBadge();
      final controller = UnreadController(
        api: api,
        tokenProvider: () async => 'token',
        badgeChannel: badge,
      );

      await controller.refresh();
      count = 1;
      await controller.refresh();
      count = 3;
      await controller.refresh();
      await controller.markRead('consultation');

      expect(badge.calls, [0, 1, 3, 0, 0]);
    },
  );

  test('successful account deletion clears a stale launcher badge', () async {
    var count = 1;
    final badge = _RecordingBadge();
    final controller = UnreadController(
      api: UnreadApi(
        ApiClient(
          baseUrl: 'http://test.local',
          httpClient: MockClient((request) async {
            if (request.url.path == '/api/app/unread') {
              return http.Response(
                jsonEncode({
                  'counts': {'consultation': count},
                }),
                200,
              );
            }
            return http.Response('{}', 404);
          }),
        ),
      ),
      tokenProvider: () async => 'account-a-token',
      badgeChannel: badge,
    );

    await controller.refresh();
    controller.clear();

    expect(controller.consultation, 0);
    expect(badge.calls.last, 0);
  });

  test('restart after deletion resynchronizes the launcher to zero', () async {
    var count = 1;
    final badge = _RecordingBadge();
    UnreadController buildController() => UnreadController(
      api: UnreadApi(
        ApiClient(
          baseUrl: 'http://test.local',
          httpClient: MockClient((request) async {
            if (request.url.path == '/api/app/unread') {
              return http.Response(
                jsonEncode({
                  'counts': {'consultation': count},
                }),
                200,
              );
            }
            return http.Response('{}', 404);
          }),
        ),
      ),
      tokenProvider: () async => 'account-a-token',
      badgeChannel: badge,
    );

    final first = buildController();
    await first.refresh();
    first.clear();
    count = 0;

    final afterRestart = buildController();
    await afterRestart.refresh();

    expect(afterRestart.consultation, 0);
    expect(badge.calls.last, 0);
  });

  test(
    'a new account cannot inherit a late unread response from the old one',
    () async {
      final pending = Completer<http.Response>();
      final badge = _RecordingBadge();
      final controller = UnreadController(
        api: UnreadApi(
          ApiClient(
            baseUrl: 'http://test.local',
            httpClient: MockClient((request) async => pending.future),
          ),
        ),
        tokenProvider: () async => 'old-account-token',
        badgeChannel: badge,
      );

      final refresh = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      controller.clear();
      pending.complete(
        http.Response(
          jsonEncode({
            'counts': {'consultation': 1},
          }),
          200,
        ),
      );
      await refresh;

      expect(controller.consultation, 0);
      expect(badge.calls.last, 0);
    },
  );

  test('logout clears the launcher badge even when local unread is empty', () {
    final badge = _RecordingBadge();
    final controller = UnreadController(
      api: UnreadApi(
        ApiClient(
          baseUrl: 'http://test.local',
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
      ),
      tokenProvider: () async => null,
      badgeChannel: badge,
    );

    controller.clear();

    expect(badge.calls, [0]);
  });

  test('first install is silent, then a new build is announced once', () async {
    final preferences = await SharedPreferences.getInstance();

    expect(
      await AppUpdateAlertService.claimUpdate(
        preferences: preferences,
        build: '1.0.0+1',
      ),
      isFalse,
    );
    expect(
      await AppUpdateAlertService.claimUpdate(
        preferences: preferences,
        build: '1.0.0+1',
      ),
      isFalse,
    );
    expect(
      await AppUpdateAlertService.claimUpdate(
        preferences: preferences,
        build: '1.0.0+2',
      ),
      isTrue,
    );
    expect(
      await AppUpdateAlertService.claimUpdate(
        preferences: preferences,
        build: '1.0.0+2',
      ),
      isFalse,
    );
  });
}
