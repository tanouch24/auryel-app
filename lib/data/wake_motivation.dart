import 'dart:convert';

import 'package:flutter/services.dart';

import 'wake_message.dart';

class WakeMotivation {
  const WakeMotivation({
    required this.id,
    required this.text,
    required this.audioAsset,
  });

  final String id;
  final String text;
  final String audioAsset;

  WakeMessage toMessage() =>
      WakeMessage(id: id, text: text, audioAsset: audioAsset);
}

class WakeMotivationCatalog {
  static const _jsonAsset = 'assets/wake_motivations/motivations.json';
  static const _audioPrefix = 'assets/wake_motivations/audios/';

  static Future<List<WakeMotivation>> load() async {
    final raw = await rootBundle.loadString(_jsonAsset);
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map((entry) {
          final id = entry['id'];
          final text = entry['text'];
          final audio = entry['audio_file'];
          if (id is! String ||
              text is! String ||
              audio is! String ||
              id.trim().isEmpty ||
              text.trim().isEmpty ||
              audio.trim().isEmpty) {
            throw const FormatException('Motivation Réveil invalide');
          }
          return WakeMotivation(
            id: id.trim(),
            text: text.trim(),
            audioAsset: '$_audioPrefix${audio.trim()}',
          );
        })
        .toList(growable: false);
  }

  static WakeMotivation? pick(List<WakeMotivation> items, DateTime date) {
    if (items.isEmpty) return null;
    final dayOfYear = date.difference(DateTime(date.year)).inDays;
    return items[dayOfYear % items.length];
  }
}
