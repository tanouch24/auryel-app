import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_record.dart';

/// Abstraction de persistance de l'onboarding. Au Temps 2, une implémentation
/// basée sur l'API serveur (comptes réels, `user_id` Auryel) pourra remplacer
/// [LocalOnboardingRepository] sans qu'aucun écran n'ait à changer.
abstract class OnboardingRepository {
  Future<OnboardingRecord?> load();
  Future<void> save(OnboardingRecord record);
  Future<void> clear();
}

/// Implémentation MOCK Temps 1 — stockage local via `shared_preferences`,
/// isolé derrière un unique clé JSON. Aucun appel réseau.
class LocalOnboardingRepository implements OnboardingRepository {
  static const _storageKey = 'auryel_onboarding_v1';

  @override
  Future<OnboardingRecord?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return null;
    try {
      return OnboardingRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Donnée mock corrompue/obsolète : on l'ignore plutôt que de crasher.
      return null;
    }
  }

  @override
  Future<void> save(OnboardingRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(record.toJson()));
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
