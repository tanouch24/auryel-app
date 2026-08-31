/// Jeu des 22 arcanes majeurs du Tarot — données du Tirage.
///
/// `key`, `name`, `interpretation` et `role` sont portés FIDÈLEMENT depuis
/// `auryeltiktok/generators/tarot.py` (dict `ARCANA`) — même formulation, même
/// ponctuation. Ne pas réécrire ni inventer : la formulation « officielle »
/// vit dans ce fichier source et doit rester alignée.
///
/// `assetPath` pointe vers les PNG copiés sous `assets/images/tarot/<key>.png`
/// (215×379, arcanes face visible). Le dos de carte reste dessiné en widget
/// dans l'écran Tirage — aucun asset dos.
class TarotArcana {
  const TarotArcana({
    required this.key,
    required this.name,
    required this.assetPath,
    required this.interpretation,
    required this.role,
  });

  /// Slug stable, identique au nom de fichier et à la clé backend (`ARCANA`).
  final String key;

  /// Nom de l'arcane tel qu'écrit dans la source (majuscules).
  final String name;

  /// `assets/images/tarot/<key>.png`.
  final String assetPath;

  /// Interprétation courte (1 phrase), portée telle quelle depuis la source.
  final String interpretation;

  /// Rôle de la carte pour une lecture combinée, porté tel quel depuis la source.
  final String role;
}

/// Les 22 arcanes majeurs, dans l'ordre traditionnel : Le Fou (0), puis I → XXI.
const List<TarotArcana> kTarotMajorArcana = [
  TarotArcana(
    key: 'le_fou',
    name: 'LE FOU',
    assetPath: 'assets/images/tarot/le_fou.png',
    interpretation: "Le Fou indique qu'un nouveau commencement spontané ou inattendu va se présenter.",
    role: 'nouveau départ spontané et inattendu, liberté retrouvée, commencement imprévu',
  ),
  TarotArcana(
    key: 'le_bateleur',
    name: 'LE BATELEUR',
    assetPath: 'assets/images/tarot/le_bateleur.png',
    interpretation: 'Le Bateleur indique que tu possèdes toutes les ressources pour agir maintenant.',
    role:
        "pouvoir d'action immédiat, ressources disponibles, prise d'initiative",
  ),
  TarotArcana(
    key: 'la_papesse',
    name: 'LA PAPESSE',
    assetPath: 'assets/images/tarot/la_papesse.png',
    interpretation:
        "La Papesse indique qu'une vérité intérieure attend d'être écoutée.",
    role: 'intuition profonde, savoir caché, vérité intérieure non écoutée',
  ),
  TarotArcana(
    key: 'l_imperatrice',
    name: "L'IMPÉRATRICE",
    assetPath: 'assets/images/tarot/l_imperatrice.png',
    interpretation:
        "L'Impératrice signale une phase de renouveau et d'abondance.",
    role: 'abondance, renouveau, création, nouvelle phase positive',
  ),
  TarotArcana(
    key: 'l_empereur',
    name: "L'EMPEREUR",
    assetPath: 'assets/images/tarot/l_empereur.png',
    interpretation: "L'Empereur indique qu'une structure ou une autorité joue un rôle central.",
    role: 'contrôle repris, autorité, structure, stabilité nécessaire',
  ),
  TarotArcana(
    key: 'le_pape',
    name: 'LE PAPE',
    assetPath: 'assets/images/tarot/le_pape.png',
    interpretation: 'Le Pape indique qu\'une décision doit être alignée avec tes convictions profondes.',
    role: 'décision selon ses valeurs, conscience morale, choix réfléchi',
  ),
  TarotArcana(
    key: 'l_amoureux',
    name: 'LES AMOUREUX',
    assetPath: 'assets/images/tarot/l_amoureux.png',
    interpretation: "Les Amoureux indiquent qu'une décision cruciale concerne une relation ou un engagement.",
    role:
        'choix amoureux déterminant, connexion profonde, engagement ou rupture',
  ),
  TarotArcana(
    key: 'le_chariot',
    name: 'LE CHARIOT',
    assetPath: 'assets/images/tarot/le_chariot.png',
    interpretation: 'Le Chariot indique une progression et un succès à portée grâce à la volonté.',
    role: 'victoire proche, progression active, volonté qui triomphe',
  ),
  TarotArcana(
    key: 'la_justice',
    name: 'LA JUSTICE',
    assetPath: 'assets/images/tarot/la_justice.png',
    interpretation: 'La Justice indique qu\'une situation va être clarifiée et les responsabilités établies.',
    role: 'vérité révélée, clarification imminente, équilibre rétabli',
  ),
  TarotArcana(
    key: 'l_ermite',
    name: "L'ERMITE",
    assetPath: 'assets/images/tarot/l_ermite.png',
    interpretation: "L'Ermite indique une période de retrait nécessaire pour trouver une réponse intérieure.",
    role: 'recul nécessaire, solitude productive, réponse à trouver seul',
  ),
  TarotArcana(
    key: 'la_roue_de_fortune',
    name: 'LA ROUE DE FORTUNE',
    assetPath: 'assets/images/tarot/la_roue_de_fortune.png',
    interpretation: 'La Roue de Fortune annonce un changement de cycle imminent dans ta situation.',
    role:
        'changement de cycle imminent, tournant inattendu, destin en mouvement',
  ),
  TarotArcana(
    key: 'la_force',
    name: 'LA FORCE',
    assetPath: 'assets/images/tarot/la_force.png',
    interpretation: 'La Force indique que tu possèdes la capacité intérieure de surmonter ce qui résiste.',
    role:
        'force intérieure disponible, obstacles surmontables, courage qui paie',
  ),
  TarotArcana(
    key: 'le_pendu',
    name: 'LE PENDU',
    assetPath: 'assets/images/tarot/le_pendu.png',
    interpretation: 'Le Pendu indique qu\'agir maintenant serait prématuré — une attente stratégique est nécessaire.',
    role: 'attente stratégique obligatoire, moment pas encore venu, nouvelle perspective à adopter',
  ),
  TarotArcana(
    key: 'la_mort',
    name: 'LA MORT',
    assetPath: 'assets/images/tarot/la_mort.png',
    interpretation: 'La Mort indique une transformation profonde — quelque chose doit se terminer pour du neuf.',
    role: 'fin nécessaire d\'un cycle, transformation radicale, nouveau départ imposé',
  ),
  TarotArcana(
    key: 'temperance',
    name: 'LA TEMPÉRANCE',
    assetPath: 'assets/images/tarot/temperance.png',
    interpretation: 'La Tempérance indique qu\'une situation instable retrouve progressivement son équilibre.',
    role: 'équilibre en cours de rétablissement, harmonie retrouvée, réconciliation possible',
  ),
  TarotArcana(
    key: 'le_diable',
    name: 'LE DIABLE',
    assetPath: 'assets/images/tarot/le_diable.png',
    interpretation: 'Le Diable indique un attachement ou une dépendance qui bloque un mouvement nécessaire.',
    role: 'attachement toxique qui bloque, dépendance à une situation ou personne, chaîne invisible',
  ),
  TarotArcana(
    key: 'la_maison_dieu',
    name: 'LA MAISON DIEU',
    assetPath: 'assets/images/tarot/la_maison_dieu.png',
    interpretation: 'La Maison Dieu annonce la destruction soudaine d\'une structure qui ne tenait plus.',
    role: 'rupture brutale libératrice, révélation forcée, effondrement nécessaire',
  ),
  TarotArcana(
    key: 'l_etoile',
    name: "L'ÉTOILE",
    assetPath: 'assets/images/tarot/l_etoile.png',
    interpretation: "L'Étoile indique que la situation évolue vers une guérison et un renouveau authentique.",
    role: 'espoir fondé sur des bases réelles, guérison en cours, renouveau après la crise',
  ),
  TarotArcana(
    key: 'la_lune',
    name: 'LA LUNE',
    assetPath: 'assets/images/tarot/la_lune.png',
    interpretation: 'La Lune indique qu\'une vérité n\'a pas encore été révélée et que la situation reste floue.',
    role: 'vérité cachée délibérément, illusion entretenue, secret non révélé',
  ),
  TarotArcana(
    key: 'le_soleil',
    name: 'LE SOLEIL',
    assetPath: 'assets/images/tarot/le_soleil.png',
    interpretation: 'Le Soleil annonce une clarification positive et une période favorable qui s\'ouvre.',
    role: 'bonne nouvelle concrète, clarification positive, succès confirmé',
  ),
  TarotArcana(
    key: 'le_jugement',
    name: 'LE JUGEMENT',
    assetPath: 'assets/images/tarot/le_jugement.png',
    interpretation: "Le Jugement indique qu'une situation n'est pas terminée et qu'un retour reste possible.",
    role: 'retour ou contact possible, situation non close, renaissance d\'une relation',
  ),
  TarotArcana(
    key: 'le_monde',
    name: 'LE MONDE',
    assetPath: 'assets/images/tarot/le_monde.png',
    interpretation: "Le Monde indique l'accomplissement d'un cycle complet et une conclusion réussie.",
    role:
        'accomplissement total, cycle complètement terminé, réussite confirmée',
  ),
];

/// Accès par `key` (slug). `null` si la clé est inconnue.
TarotArcana? tarotArcanaByKey(String key) {
  for (final arcana in kTarotMajorArcana) {
    if (arcana.key == key) return arcana;
  }
  return null;
}
