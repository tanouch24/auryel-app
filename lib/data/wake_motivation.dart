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
  static const _phrasesAsset = 'assets/wake_motivations/phrases.txt';

  static Future<List<WakeMotivation>> load() async {
    final raw = await rootBundle.loadString(_jsonAsset);
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final phraseLines = (await rootBundle.loadString(_phrasesAsset))
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (phraseLines.length != 50) {
      throw const FormatException('Phrases Réveil incomplètes');
    }
    final items = decoded
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
    if (items.length != 50 || items.map((item) => item.id).toSet().length != 50) {
      throw const FormatException('Catalogue Réveil invalide');
    }
    for (var index = 0; index < items.length; index++) {
      final expectedId = 'motivation_${(index + 1).toString().padLeft(3, '0')}';
      final line = phraseLines[index];
      final separator = line.indexOf('—');
      final lineId = separator > 0 ? line.substring(0, separator).trim() : '';
      final lineText = separator > 0 ? line.substring(separator + 1).trim() : '';
      if (items[index].id != expectedId ||
          lineId != (index + 1).toString().padLeft(3, '0') ||
          lineText != items[index].text ||
          items[index].audioAsset != '$_audioPrefix$expectedId.mp3') {
        throw FormatException('Désynchronisation de la motivation ${index + 1}');
      }
    }
    return items;
  }

  static WakeMotivation? pick(List<WakeMotivation> items, DateTime date) {
    if (items.isEmpty) return null;
    final dayOfYear = date.difference(DateTime(date.year)).inDays;
    return items[dayOfYear % items.length];
  }
}
