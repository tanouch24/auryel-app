import 'package:flutter/foundation.dart';

import 'exercise.dart';
import 'meditation_item.dart';

@immutable
class ContentRecommendation {
  const ContentRecommendation({
    required this.recommendationId,
    required this.type,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.coverUrl,
    this.pdfUrl,
    this.audioUrl,
    this.imageUrl,
    this.description = '',
    this.category = '',
    this.durationSeconds = 0,
    this.level = '',
    this.steps = const [],
    this.precautions = '',
    this.sortOrder = 0,
    this.version = 1,
    this.navigationOnly = false,
  });

  final String recommendationId;
  final String type;
  final String id;
  final String title;
  final String subtitle;
  final String? coverUrl;
  final String? pdfUrl;
  final String? audioUrl;
  final String? imageUrl;
  final String description;
  final String category;
  final int durationSeconds;
  final String level;
  final List<Map<String, dynamic>> steps;
  final String precautions;
  final int sortOrder;
  final int version;

  /// New meditation recommendations navigate to the library only. Historical
  /// rows omit this field and retain their legacy card behavior.
  final bool navigationOnly;

  bool get isEbook => type == 'ebook';
  bool get isMeditation => type == 'meditation';
  bool get isExercise => type == 'exercise';

  factory ContentRecommendation.tryFromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('recommendation');
    final type = (raw['content_type'] ?? raw['type'] ?? '').toString().trim();
    final id = (raw['content_id'] ?? raw['id'] ?? '').toString().trim();
    final title = (raw['title'] ?? '').toString().trim();
    final recommendationId =
        (raw['recommendation_id'] ?? raw['id_recommendation'] ?? '').toString();
    if (!{'ebook', 'meditation', 'exercise'}.contains(type) ||
        id.isEmpty ||
        title.isEmpty ||
        recommendationId.isEmpty) {
      throw const FormatException('recommendation');
    }
    final rawSteps = raw['steps'];
    final steps = rawSteps is List
        ? rawSteps
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(growable: false)
        : const <Map<String, dynamic>>[];
    return ContentRecommendation(
      recommendationId: recommendationId,
      type: type,
      id: id,
      title: title,
      subtitle: _text(raw['subtitle']),
      coverUrl: _url(raw['cover_url']),
      pdfUrl: _url(raw['pdf_url']),
      audioUrl: _url(raw['audio_url']),
      imageUrl: _url(raw['image_url']),
      description: _text(raw['description']),
      category: _text(raw['category']),
      durationSeconds: _int(raw['duration_seconds']),
      level: _text(raw['level']),
      steps: steps,
      precautions: _text(raw['precautions']),
      sortOrder: _int(raw['sort_order']),
      version: _int(raw['version'], fallback: 1),
      navigationOnly: raw['navigation_only'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'slug': id,
    'title': title,
    'content_type': type,
    'description': description,
    'category': category,
    'duration_seconds': durationSeconds,
    'audio_url': audioUrl,
    'image_url': imageUrl,
    'level': level,
    'steps': steps,
    'precautions': precautions,
    'sort_order': sortOrder,
    'version': version,
    'navigation_only': navigationOnly,
  };

  MeditationItem? asMeditation() =>
      isMeditation ? MeditationItem.tryFromJson(toJson()) : null;

  Exercise? asExercise() => isExercise ? Exercise.tryFromJson(toJson()) : null;
}

String _text(Object? value) => value is String ? value.trim() : '';
String? _url(Object? value) {
  final v = _text(value);
  return v.isEmpty ? null : v;
}

int _int(Object? value, {int fallback = 0}) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ?? fallback;
