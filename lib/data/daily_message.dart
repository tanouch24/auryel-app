/// Message du jour — modèle propre `message + interprétation`, prêt à être
/// branché sur le contenu calendaire serveur (B8.x / B10). Pour l'instant les
/// valeurs sont EN DUR ici (aucun appel LLM, aucune génération) : un seul point
/// à remplacer quand l'API contenu du jour existera.
///
/// Ton de l'interprétation : évocateur, jamais prédictif — aucune certitude,
/// aucune promesse. Vocabulaire interdit repris du cadrage produit : pas de
/// « coaching », « psychologique », « guidance » dans le texte affiché.
class DailyMessage {
  const DailyMessage({
    required this.leadText,
    required this.accentText,
    required this.interpretation,
    required this.dateLabel,
  });

  /// Début de la phrase, rendu en style normal.
  final String leadText;

  /// Fin de la phrase, rendue en italique doré (accent visuel).
  final String accentText;

  /// Lecture courte du message — affichée dans la feuille de détail et reprise
  /// telle quelle dans le partage texte de repli.
  final String interpretation;

  /// Étiquette de date déjà formatée (ex. « MARDI 25 AOÛT »).
  final String dateLabel;

  /// Phrase complète (affichage simple + partage).
  String get text => '$leadText$accentText';

  /// Message du jour courant. SEUL endroit à rebrancher sur l'API plus tard.
  static const DailyMessage today = DailyMessage(
    leadText: 'Ce que tu n’oses pas regarder ',
    accentText: 'te dirige.',
    dateLabel: 'MARDI 25 AOÛT',
    interpretation:
        'Il y a souvent une pensée qu’on repousse parce qu’elle dérange : '
        'un doute sur une relation, une décision qu’on évite, une vérité qu’on '
        'connaît déjà. Tant qu’elle reste dans l’ombre, c’est elle qui mène. '
        'La regarder en face, même une minute, suffit parfois à reprendre la '
        'main. Aujourd’hui, demande-toi simplement : qu’est-ce que j’évite de '
        'nommer ?',
  );
}
