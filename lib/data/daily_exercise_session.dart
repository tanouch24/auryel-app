import 'exercise.dart';

/// Sélection déterministe de la séance du jour. Elle ne dépend ni du rebuild
/// Flutter ni d'un générateur aléatoire : même catalogue + même date donnent
/// toujours les mêmes cinq exercices.
List<Exercise> dailyExerciseSession(
  List<Exercise> source, {
  required DateTime day,
}) {
  final active = [...source]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  if (active.length <= 5) return List.unmodifiable(active);
  final dayKey = '${day.year}-${day.month}-${day.day}';
  final categories = <String>{for (final e in active) e.category}.toList()..sort();
  final selected = <Exercise>[];
  for (final category in categories) {
    final candidates = active.where((e) => e.category == category).toList()
      ..sort((a, b) => _score('$dayKey:${a.slug}').compareTo(_score('$dayKey:${b.slug}')));
    if (candidates.isNotEmpty) selected.add(candidates.first);
  }
  final remaining = active.where((e) => !selected.contains(e)).toList()
    ..sort((a, b) => _score('$dayKey:${a.slug}').compareTo(_score('$dayKey:${b.slug}')));
  selected.addAll(remaining.take(5 - selected.length));
  return List.unmodifiable(selected.take(5));
}

int _score(String value) {
  var hash = 2166136261;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0x7fffffff;
  }
  return hash;
}
