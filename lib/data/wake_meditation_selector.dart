import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'content_repository.dart';
import 'meditation_item.dart';
import 'relaxation_video.dart';
import 'relaxation_video_selector.dart';

/// Sélection quotidienne du Réveil. Le catalogue vient du serveur/cache ; la
/// date et l'identifiant retenu sont persistés afin qu'un snooze ne change
/// jamais de séance.
class WakeMeditationSelection {
  WakeMeditationSelection({SharedPreferences? prefs}) : _injectedPrefs = prefs;

  final SharedPreferences? _injectedPrefs;
  static const _key = 'auryel.wake.meditation_day.v1';

  Future<SharedPreferences> get _prefs async =>
      _injectedPrefs ?? await SharedPreferences.getInstance();

  Future<({MeditationItem item, RelaxationVideo? video})?> pick(
    ContentRepository repository,
    DateTime now,
  ) async {
    final catalog = await repository.meditations();
    if (catalog.isEmpty) return null;
    final day = ContentRepository.dayString(now);
    final p = await _prefs;
    final previous = p.getString(_key);
    MeditationItem? item;
    if (previous != null) {
      try {
        final saved = jsonDecode(previous);
        if (saved is Map && saved['day'] == day) {
          final id = saved['id'];
          for (final candidate in catalog) {
            if (candidate.id == id) {
              item = candidate;
              break;
            }
          }
        }
      } catch (_) {}
    }
    if (item == null) {
      final recent = <String>{};
      try {
        final history =
            p.getStringList('auryel.wake.meditation_history.v1') ?? [];
        recent.addAll(history.take(3));
      } catch (_) {}
      final candidates = catalog.where((m) => !recent.contains(m.id)).toList();
      final pool = candidates.isEmpty ? catalog : candidates;
      final index = _stableIndex(day, pool.length);
      item = pool[index];
      await p.setString(_key, jsonEncode({'day': day, 'id': item.id}));
      final history = [item.id, ...recent].take(3).toList();
      await p.setStringList('auryel.wake.meditation_history.v1', history);
    }

    RelaxationVideo? video;
    final direct = item.videoUrl;
    if (direct != null &&
        (direct.startsWith('http://') || direct.startsWith('https://'))) {
      video = RelaxationVideo(
        id: '${item.id}-video',
        slug: '${item.id}-video',
        title: item.title,
        videoUrl: direct,
        category: item.category.name,
      );
    } else {
      final videos = await repository.relaxationVideos();
      video = RelaxationVideoSelector().choose(
        videos,
        meditationCategory: item.category.name,
      );
    }
    return (item: item, video: video);
  }

  static int _stableIndex(String day, int length) {
    if (length <= 1) return 0;
    var hash = 0;
    for (final code in day.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash % length;
  }
}
