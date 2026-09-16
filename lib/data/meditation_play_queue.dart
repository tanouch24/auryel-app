import 'dart:math';

import 'relaxation_video.dart';

/// File de lecture locale : chaque élément est parcouru une fois par cycle.
/// Elle ne modifie jamais le catalogue serveur ni les identifiants des médias.
class MeditationPlayQueue {
  MeditationPlayQueue(
    List<RelaxationVideo> videos, {
    Random? random,
    this.lastPlayedSlug,
  }) : _random = random ?? Random(),
       _items = const [],
       _index = 0 {
    _items = _shuffled(videos, _random, lastPlayedSlug);
  }

  final Random _random;
  final String? lastPlayedSlug;
  List<RelaxationVideo> _items;
  int _index;

  List<RelaxationVideo> get items => List.unmodifiable(_items);
  int get index => _index;
  RelaxationVideo? get current => _items.isEmpty ? null : _items[_index];

  RelaxationVideo? next() {
    if (_items.isEmpty) return null;
    if (_index == _items.length - 1) {
      final previous = _items[_index].slug;
      _items = _shuffled(_items, _random, previous);
      _index = 0;
    } else {
      _index++;
    }
    return current;
  }

  RelaxationVideo? previous() {
    if (_items.isEmpty) return null;
    _index = _index == 0 ? _items.length - 1 : _index - 1;
    return current;
  }

  void moveTo(int index) {
    if (index >= 0 && index < _items.length) _index = index;
  }

  static List<RelaxationVideo> _shuffled(
    List<RelaxationVideo> source,
    Random random,
    String? avoidFirst,
  ) {
    final result = [...source]..shuffle(random);
    if (result.length > 1 &&
        avoidFirst != null &&
        result.first.slug == avoidFirst) {
      final other = result.indexWhere((video) => video.slug != avoidFirst);
      if (other > 0) {
        final first = result.first;
        result[0] = result[other];
        result[other] = first;
      }
    }
    return result;
  }
}

/// Nettoyage visuel uniquement. La valeur originale reste utilisée pour
/// l'identification, le cache et l'URL du média.
String meditationDisplayTitle(String source) {
  return source.replaceFirst(RegExp(r'\s+\d+$'), '').trim();
}
