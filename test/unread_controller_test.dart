import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/unread_api.dart';
import 'package:auryel/state/unread_controller.dart';

void main() {
  test(
    'unread advisor indicator follows refresh and mark-read state',
    () async {
      var unread = 1;
      final client = ApiClient(
        baseUrl: 'http://test.local',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/app/unread') {
            return http.Response(
              jsonEncode({
                'counts': {'consultation': unread},
              }),
              200,
            );
          }
          if (request.url.path == '/api/app/unread/read') {
            unread = 0;
            return http.Response(
              jsonEncode({'status': 'ok', 'marked': 1}),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );
      final controller = UnreadController(
        api: UnreadApi(client),
        tokenProvider: () async => 'token',
      );

      await controller.refresh();
      controller.noteConsultationAdvisor('thea');
      expect(controller.consultation, 1);
      expect(controller.consultationAdvisorIds, contains('thea'));

      await controller.markRead('consultation');
      expect(controller.consultation, 0);
      expect(controller.consultationAdvisorIds, isEmpty);
    },
  );
}
