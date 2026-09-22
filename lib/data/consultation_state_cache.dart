import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'consultation.dart';

/// Dernier état quota vérifié par le serveur, utilisé uniquement pour rendre
/// l'interface stable pendant une panne réseau. Les actions protégées restent
/// autorisées par le backend ; ce cache ne crédite ni ne prolonge rien.
class ConsultationStateCache {
  ConsultationStateCache({SharedPreferences? prefs}) : _injected = prefs;

  final SharedPreferences? _injected;
  static const _prefix = 'auryel.consultation.last_verified.v1.';

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  String _key(String userId) => '$_prefix$userId';

  Future<void> save({
    required String userId,
    required QuotaDto quota,
    required ConsultationTimeState? time,
  }) async {
    if (userId.isEmpty) return;
    await (await _prefs).setString(
      _key(userId),
      jsonEncode({
        'quota': quota.toJson(),
        if (time != null) 'time': time.toJson(),
      }),
    );
  }

  Future<({QuotaDto quota, ConsultationTimeState? time})?> load({
    required String userId,
  }) async {
    if (userId.isEmpty) return null;
    final raw = (await _prefs).getString(_key(userId));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final q = decoded['quota'];
      if (q is! Map<String, dynamic>) return null;
      return (
        quota: QuotaDto.fromJson(q),
        time: ConsultationTimeState.maybeFromJson(decoded['time']),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear({required String userId}) async {
    if (userId.isEmpty) return;
    await (await _prefs).remove(_key(userId));
  }
}
