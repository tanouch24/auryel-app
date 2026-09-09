import 'meditation_item.dart';

/// Catalogue LOCAL des séances « Ton Moment ». Aucune API, aucun LLM : la
/// sélection du jour est purement déterministe (basée sur la date locale), le
/// même contenu toute la journée, un contenu différent le lendemain.
///
/// Le catalogue reste volontairement court (une séance par registre) : on ne
/// gonfle pas artificiellement une bibliothèque de séances fictives. Quand le
/// pack audio `assets/meditations/*` sera fourni, il suffira de compléter les
/// entrées / durées ici.
class MeditationCatalog {
  const MeditationCatalog();

  /// Séances disponibles, ordre stable (sert de base au calcul du jour).
  static const List<MeditationItem> items = [
    MeditationItem(
      id: 'respiration_calme',
      title: 'Respiration du calme',
      description: 'Trois minutes de souffle lent, pour relâcher les épaules.',
      assetPath: 'meditations/respiration_calme.m4a',
      duration: Duration(minutes: 3),
      category: MeditationCategory.respiration,
    ),
    MeditationItem(
      id: 'poser_la_journee',
      title: 'Poser la journée',
      description: 'Un moment pour ralentir avant de passer à la suite.',
      assetPath: 'meditations/poser_la_journee.m4a',
      duration: Duration(minutes: 6),
      category: MeditationCategory.detente,
    ),
    MeditationItem(
      id: 'revenir_a_toi',
      title: 'Revenir à toi',
      description: 'Un recentrage court quand les pensées partent trop vite.',
      assetPath: 'meditations/revenir_a_toi.m4a',
      duration: Duration(minutes: 5),
      category: MeditationCategory.recentrage,
    ),
    MeditationItem(
      id: 'deposer_le_jour',
      title: 'Déposer le jour',
      description: 'Pour t’aider à décrocher et glisser vers le sommeil.',
      assetPath: 'meditations/deposer_le_jour.m4a',
      duration: Duration(minutes: 8),
      category: MeditationCategory.sommeil,
    ),
    MeditationItem(
      id: 'laisser_passer',
      title: 'Laisser passer',
      description: 'Un temps pour lâcher ce que tu ne peux pas contrôler.',
      assetPath: 'meditations/laisser_passer.m4a',
      duration: Duration(minutes: 7),
      category: MeditationCategory.lacherPrise,
    ),
  ];

  /// Toutes les séances embarquées (fallback quand ni serveur ni cache n'ont de
  /// catalogue exploitable).
  List<MeditationItem> get all => items;

  /// Index déterministe de la séance « du jour » dans une liste de `length`
  /// entrées : `((jours depuis l'origine % length) + length) % length` (robuste
  /// aux valeurs négatives). Réutilisé pour le catalogue distant.
  static int indexForDay(DateTime now, int length) {
    if (length <= 0) return 0;
    final origin = DateTime(2026, 1, 1);
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(origin).inDays;
    return ((days % length) + length) % length;
  }

  /// La séance « du jour » — déterministe, stable sur 24 h locales.
  MeditationItem momentOfDay(DateTime now) =>
      items[indexForDay(now, items.length)];
}
