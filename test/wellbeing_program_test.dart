import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/wellbeing_program_api.dart';
import 'package:auryel/state/wellbeing_program_controller.dart';

http.Response _json(Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _state({
  String status = 'active',
  int completed = 0,
  String? pdfUrl,
}) => {
  'status': status,
  'timezone': 'Europe/Paris',
  'ebook': {
    'title': '30 jours pour prendre soin de soi',
    'subtitle': 'Le petit guide Bien-être Auryel',
    'pdf_url': pdfUrl,
    'version': 1,
    'active': true,
  },
  'program': {
    'started_at': '2026-09-14T08:00:00+00:00',
    'completed_at': null,
    'reminder_enabled': false,
  },
  'today': {
    'day_number': 1,
    'date': '2026-09-14',
    'completed_count': completed,
    'completed': completed == 5,
    'actions': [
      for (var i = 1; i <= 5; i++)
        {
          'day_number': 1,
          'action_slot': i,
          'text': 'Action réelle $i',
          'category': 'calme',
          'completed': i <= completed,
        },
    ],
  },
  'summary': {
    'days_with_actions': completed > 0 ? 1 : 0,
    'total_actions': completed,
  },
};

void main() {
  test(
    'le programme conserve cinq actions et la progression serveur',
    () async {
      final paths = <String>[];
      final client = ApiClient(
        baseUrl: 'http://test.local',
        httpClient: MockClient((request) async {
          paths.add('${request.method} ${request.url.path}');
          return _json(_state(completed: request.method == 'POST' ? 1 : 0));
        }),
      );
      final controller = WellbeingProgramController(
        api: WellbeingProgramApi(client),
        tokenProvider: () async => 'token',
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      expect(controller.state!.today!.actions, hasLength(5));
      expect(controller.state!.today!.completedCount, 0);
      await controller.completeAction(1, 1);
      expect(controller.state!.today!.completedCount, 1);
      expect(paths, contains('GET /api/app/wellbeing-program'));
      expect(paths, contains('POST /api/app/wellbeing-program/day/1/action/1'));
    },
  );

  test('le contrat distingue ebook indisponible, cadeau et rappel', () {
    final state = WellbeingProgramState.fromJson(_state(pdfUrl: null));
    expect(state.today!.actions, hasLength(5));
    expect(state.ebook.pdfUrl, isNull);
    expect(state.reminderEnabled, isFalse);
    expect(state.started, isTrue);
  });
}
