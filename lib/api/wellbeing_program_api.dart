import 'api_client.dart';

class WellbeingProgramAction {
  const WellbeingProgramAction({
    required this.dayNumber,
    required this.actionSlot,
    required this.text,
    required this.category,
    required this.completed,
    this.completedAt,
  });

  final int dayNumber;
  final int actionSlot;
  final String text;
  final String category;
  final bool completed;
  final String? completedAt;

  factory WellbeingProgramAction.fromJson(Map<String, dynamic> json) =>
      WellbeingProgramAction(
        dayNumber: _int(json['day_number']),
        actionSlot: _int(json['action_slot']),
        text: (json['text'] ?? '').toString(),
        category: (json['category'] ?? '').toString(),
        completed: json['completed'] == true,
        completedAt: json['completed_at']?.toString(),
      );
}

class WellbeingProgramEbook {
  const WellbeingProgramEbook({
    required this.title,
    required this.subtitle,
    required this.pdfUrl,
    required this.version,
    required this.active,
  });

  final String title;
  final String subtitle;
  final String? pdfUrl;
  final int version;
  final bool active;

  factory WellbeingProgramEbook.fromJson(Map<String, dynamic> json) =>
      WellbeingProgramEbook(
        title: (json['title'] ?? '').toString(),
        subtitle: (json['subtitle'] ?? '').toString(),
        pdfUrl: json['pdf_url']?.toString(),
        version: _int(json['version']),
        active: json['active'] == true,
      );
}

class WellbeingProgramToday {
  const WellbeingProgramToday({
    required this.dayNumber,
    required this.date,
    required this.completedCount,
    required this.completed,
    required this.actions,
  });

  final int dayNumber;
  final String date;
  final int completedCount;
  final bool completed;
  final List<WellbeingProgramAction> actions;

  factory WellbeingProgramToday.fromJson(Map<String, dynamic> json) {
    final raw = json['actions'];
    final actions = raw is List
        ? raw
              .whereType<Map<String, dynamic>>()
              .map(WellbeingProgramAction.fromJson)
              .toList(growable: false)
        : const <WellbeingProgramAction>[];
    return WellbeingProgramToday(
      dayNumber: _int(json['day_number']),
      date: (json['date'] ?? '').toString(),
      completedCount: _int(json['completed_count']),
      completed: json['completed'] == true,
      actions: actions,
    );
  }
}

class WellbeingProgramSummary {
  const WellbeingProgramSummary({
    required this.daysWithActions,
    required this.totalActions,
  });

  final int daysWithActions;
  final int totalActions;

  factory WellbeingProgramSummary.fromJson(Map<String, dynamic> json) =>
      WellbeingProgramSummary(
        daysWithActions: _int(json['days_with_actions']),
        totalActions: _int(json['total_actions']),
      );
}

class WellbeingProgramState {
  const WellbeingProgramState({
    required this.status,
    required this.timezone,
    required this.ebook,
    required this.today,
    required this.summary,
    this.startedAt,
    this.completedAt,
    this.reminderEnabled = false,
  });

  final String status;
  final String timezone;
  final WellbeingProgramEbook ebook;
  final WellbeingProgramToday? today;
  final WellbeingProgramSummary summary;
  final String? startedAt;
  final String? completedAt;
  final bool reminderEnabled;

  bool get started => today != null;
  bool get completed => status == 'completed';

  factory WellbeingProgramState.fromJson(Map<String, dynamic> json) {
    final program = json['program'];
    final programMap = program is Map<String, dynamic> ? program : const {};
    final today = json['today'];
    final summary = json['summary'];
    final ebook = json['ebook'];
    return WellbeingProgramState(
      status: (json['status'] ?? 'not_started').toString(),
      timezone: (json['timezone'] ?? 'Europe/Paris').toString(),
      ebook: WellbeingProgramEbook.fromJson(
        ebook is Map<String, dynamic> ? ebook : const {},
      ),
      today: today is Map<String, dynamic>
          ? WellbeingProgramToday.fromJson(today)
          : null,
      summary: WellbeingProgramSummary.fromJson(
        summary is Map<String, dynamic> ? summary : const {},
      ),
      startedAt: programMap['started_at']?.toString(),
      completedAt: programMap['completed_at']?.toString(),
      reminderEnabled: programMap['reminder_enabled'] == true,
    );
  }
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class WellbeingProgramApi {
  WellbeingProgramApi(this._client);

  final ApiClient _client;

  Future<WellbeingProgramState> getProgram(String bearer) async =>
      WellbeingProgramState.fromJson(
        await _client.getJson('/api/app/wellbeing-program', bearer: bearer),
      );

  Future<WellbeingProgramState> start(String bearer) async =>
      WellbeingProgramState.fromJson(
        await _client.postJson(
          '/api/app/wellbeing-program/start',
          const {},
          bearer: bearer,
        ),
      );

  Future<WellbeingProgramState> completeAction({
    required String bearer,
    required int dayNumber,
    required int actionSlot,
  }) async => WellbeingProgramState.fromJson(
    await _client.postJson(
      '/api/app/wellbeing-program/day/$dayNumber/action/$actionSlot',
      const {},
      bearer: bearer,
    ),
  );

  Future<WellbeingProgramState> setReminder({
    required String bearer,
    required bool enabled,
  }) async => WellbeingProgramState.fromJson(
    await _client.postJson('/api/app/wellbeing-program/reminder', {
      'enabled': enabled,
    }, bearer: bearer),
  );
}
