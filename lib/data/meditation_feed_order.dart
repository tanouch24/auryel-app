import 'dart:math';

/// Ordre de présentation du feed Méditation — « sac mélangé » (shuffle-bag) :
/// un tirage sans répétition mélange TOUT le catalogue une fois (« une
/// méditation ne doit pas revenir avant que les autres aient eu la
/// possibilité d'être présentées »), puis, à l'épuisement, remélange pour le
/// tour suivant EN évitant que le DERNIER élément d'un tour redevienne le
/// PREMIER élément du tour suivant (« éviter les répétitions immédiates » à
/// la jointure).
///
/// Pure et déterministe via [random] injectable -> testable sans I/O.
class MeditationFeedOrder {
  MeditationFeedOrder({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// Mélange [items] (copie, ne modifie jamais la liste reçue). [items] vide
  /// ou à 1 élément -> renvoyé tel quel (rien à mélanger).
  List<T> shuffle<T>(List<T> items) {
    if (items.length <= 1) return List<T>.of(items);
    final copy = List<T>.of(items)..shuffle(_random);
    return copy;
  }

  /// Remélange pour le tour SUIVANT en évitant que [previousLast] (dernier
  /// élément du tour précédent, comparé par [T.==] — utiliser une clé stable
  /// comme un `id` si [T] n'a pas d'égalité de valeur) ne se retrouve
  /// premier du nouveau tour. Retente un nombre borné de fois puis, en
  /// dernier recours (catalogue à 1 seul élément), échange simplement avec
  /// le 2ᵉ élément si possible — jamais de boucle infinie.
  List<T> reshuffle<T>(List<T> items, T? previousLast) {
    final next = shuffle(items);
    if (previousLast == null || next.isEmpty) return next;
    if (next.length == 1) return next; // rien d'autre à proposer
    var attempts = 0;
    var result = next;
    while (result.first == previousLast && attempts < 8) {
      result = shuffle(items);
      attempts++;
    }
    if (result.first == previousLast) {
      // Dernier recours déterministe : permute les deux premiers.
      final swapped = List<T>.of(result);
      final tmp = swapped[0];
      swapped[0] = swapped[1];
      swapped[1] = tmp;
      result = swapped;
    }
    return result;
  }
}
