import 'package:flutter/foundation.dart';

@immutable
class ExerciseStep {
  const ExerciseStep({
    required this.order,
    required this.title,
    required this.instruction,
    this.seconds,
  });

  final int order;
  final String title;
  final String instruction;
  final int? seconds;

  static ExerciseStep? tryFromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final order = raw['order'];
    final title = raw['title'];
    final instruction = raw['instruction'];
    if (order is! num ||
        title is! String ||
        instruction is! String ||
        title.trim().isEmpty ||
        instruction.trim().isEmpty) {
      return null;
    }
    final seconds = raw['seconds'];
    if (seconds != null && seconds is! num) {
      return null;
    }
    return ExerciseStep(
      order: order.toInt(),
      title: title.trim(),
      instruction: instruction.trim(),
      seconds: seconds?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'order': order,
    'title': title,
    'instruction': instruction,
    if (seconds != null) 'seconds': seconds,
  };
}

@immutable
class Exercise {
  const Exercise({
    required this.id,
    required this.slug,
    required this.title,
    required this.category,
    required this.description,
    required this.durationSeconds,
    required this.level,
    required this.steps,
    required this.precautions,
    required this.sortOrder,
    required this.version,
    this.imageUrl,
  });

  final String id;
  final String slug;
  final String title;
  final String category;
  final String description;
  final int durationSeconds;
  final String level;
  final List<ExerciseStep> steps;
  final String precautions;
  final int sortOrder;
  final int version;
  final String? imageUrl;

  static Exercise? tryFromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final id = raw['id'];
    final slug = raw['slug'];
    final title = raw['title'];
    final category = raw['category'];
    final description = raw['description'];
    final duration = raw['duration_seconds'];
    final level = raw['level'];
    final rawSteps = raw['steps'];
    final precautions = raw['precautions'];
    final sortOrder = raw['sort_order'];
    final version = raw['version'];
    final imageUrl = raw['image_url'];
    if ([
          id,
          slug,
          title,
          category,
          description,
          level,
          precautions,
        ].any((v) => v is! String) ||
        duration is! num ||
        duration <= 0 ||
        sortOrder is! num ||
        version is! num ||
        rawSteps is! List ||
        (imageUrl != null && imageUrl is! String)) {
      return null;
    }
    final steps = rawSteps
        .map(ExerciseStep.tryFromJson)
        .whereType<ExerciseStep>()
        .toList();
    final parsedImageUrl = imageUrl is String && imageUrl.trim().isNotEmpty
        ? imageUrl.trim()
        : null;
    if (steps.isEmpty ||
        id.trim().isEmpty ||
        slug.trim().isEmpty ||
        title.trim().isEmpty ||
        category.trim().isEmpty) {
      return null;
    }
    return Exercise(
      id: id,
      slug: slug,
      title: title,
      category: category,
      description: description,
      durationSeconds: duration.toInt(),
      level: level,
      steps: List.unmodifiable(steps),
      precautions: precautions,
      sortOrder: sortOrder.toInt(),
      version: version.toInt(),
      imageUrl: parsedImageUrl,
    );
  }

  String get categoryLabel => switch (category) {
    'breathing' => 'Respiration',
    'relaxation' => 'Relaxation',
    'stretching' => 'Étirements',
    'mobility' => 'Mobilité',
    'sleep' => 'Sommeil',
    _ => category,
  };

  String get durationLabel {
    if (durationSeconds < 60) return '$durationSeconds s';
    final minutes = durationSeconds ~/ 60;
    return '$minutes min';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'slug': slug,
    'title': title,
    'category': category,
    'description': description,
    'duration_seconds': durationSeconds,
    'level': level,
    'steps': [for (final step in steps) step.toJson()],
    'precautions': precautions,
    'sort_order': sortOrder,
    'version': version,
    if (imageUrl != null) 'image_url': imageUrl,
  };
}
