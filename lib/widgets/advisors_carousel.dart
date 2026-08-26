import 'package:flutter/material.dart';

import '../screens/advisor_detail_screen.dart';
import '../theme/auryel_theme.dart';

/// Données d'un conseiller — carrousel de découverte + fiche détaillée. En dur
/// pour l'instant, structuré pour être branché sur des données réelles plus tard.
class AdvisorInfo {
  const AdvisorInfo({
    required this.name,
    required this.specialty,
    required this.tagline,
    required this.bio,
    required this.assetPath,
    required this.voicePath,
  });

  final String name;
  final String specialty;
  final String tagline;
  final String bio;
  final String assetPath;

  /// Chemin relatif au dossier `assets/` (convention audioplayers `AssetSource`),
  /// PAS le chemin complet utilisé par `Image.asset`.
  final String voicePath;
}

const List<AdvisorInfo> kAdvisors = [
  AdvisorInfo(
    name: 'Séléna',
    specialty: 'AMOUR & RELATIONS',
    tagline: 'Directe et posée, elle dit ce qu’elle perçoit, pas ce qu’on veut entendre.',
    bio: 'Je vais droit à ce qui compte. Quand une relation devient floue, qu’un silence s’installe ou que tu ne sais plus quoi penser de l’autre, je cherche ce qui se joue derrière les apparences. Je préfère une réponse claire à une fausse consolation. Avec moi, on regarde la situation telle qu’elle se présente, puis on avance point par point.',
    assetPath: 'assets/conseillers/selena.webp',
    voicePath: 'vocaux/selena_presentation.mp3',
  ),
  AdvisorInfo(
    name: 'Luna',
    specialty: 'AMOUR & RUPTURE',
    tagline: 'Directe et sans fausse consolation, elle dit ce qu’elle perçoit.',
    bio: 'Je suis là quand les sentiments deviennent difficiles à lire : rapprochement, distance, retour, hésitation ou relation qui n’avance plus. Mon approche est directe et intuitive. Je ne cherche pas à embellir ce que je perçois. Je t’aide à mettre des mots sur la dynamique entre vous et à regarder ce qui semble réellement se dessiner.',
    assetPath: 'assets/conseillers/luna.webp',
    voicePath: 'vocaux/luna_presentation.mp3',
  ),
  AdvisorInfo(
    name: 'Maïa',
    specialty: 'DÉCISIONS & SITUATIONS',
    tagline: 'Posée et précise, elle met de l’ordre dans le compliqué.',
    bio: 'Quand tout se mélange, j’aime remettre les éléments dans le bon ordre. Une décision à prendre, plusieurs possibilités, une situation qui traîne : je regarde les faits, les tensions et ce qui semble évoluer. Mon approche est posée et précise. Le but est que tu ressortes de l’échange avec une lecture plus nette de ce qui se passe.',
    assetPath: 'assets/conseillers/maia.webp',
    voicePath: 'vocaux/maia_presentation.mp3',
  ),
  AdvisorInfo(
    name: 'Théa',
    specialty: 'CYCLES & SCHÉMAS',
    tagline: 'Analytique, elle éclaire les cycles qui se répètent.',
    bio: 'Je m’intéresse particulièrement à ce qui se répète : les mêmes relations, les mêmes blocages, les mêmes hésitations ou les mêmes tournants. J’observe les liens entre ce que tu vis aujourd’hui et les dynamiques qui reviennent. Mon approche est analytique, mais reste simple : comprendre le mouvement de la situation pour mieux lire ce qui est en train de changer.',
    assetPath: 'assets/conseillers/thea.webp',
    voicePath: 'vocaux/thea_presentation.mp3',
  ),
  AdvisorInfo(
    name: 'Cassandre',
    specialty: 'REGARD GLOBAL',
    tagline: 'Équilibrée et sans jugement, un regard global et posé.',
    bio: 'Certaines situations ne se comprennent pas en regardant un seul détail. J’aime prendre de la hauteur et relier les différents éléments : relation, contexte, décisions, tensions et évolution possible. Mon approche est équilibrée et sans jugement. Je prends le temps de regarder l’ensemble avant de te donner une lecture claire et posée.',
    assetPath: 'assets/conseillers/cassandre.webp',
    voicePath: 'vocaux/cassandre_presentation.mp3',
  ),
  AdvisorInfo(
    name: 'Myriam',
    specialty: 'TAROT',
    tagline:
        'Rigoureuse, elle s’appuie sur le tarot pour des réponses claires.',
    bio: 'Le tarot est mon outil principal. Je l’utilise pour structurer la lecture et aller chercher ce que la situation ne montre pas immédiatement. Une question précise donne souvent un tirage beaucoup plus parlant. Je reste rigoureuse dans mon interprétation : je relie les cartes à ce que tu vis réellement, sans transformer le tirage en réponse vague ou passe-partout.',
    assetPath: 'assets/conseillers/myriam.webp',
    voicePath: 'vocaux/myriam_presentation.mp3',
  ),
  AdvisorInfo(
    name: 'Orion',
    specialty: 'DÉCISIONS & RECUL',
    tagline: 'Calme et pragmatique, il aide à prendre du recul.',
    bio: 'Quand on est au milieu d’une situation, il devient parfois difficile de distinguer ce qui compte vraiment. Mon approche est calme et pragmatique. Je cherche à séparer l’essentiel du bruit, à regarder les différentes forces en présence et à te donner une lecture sans dramatiser. On prend du recul, mais on ne contourne pas la question.',
    assetPath: 'assets/conseillers/orion.webp',
    voicePath: 'vocaux/orion_presentation.mp3',
  ),
  AdvisorInfo(
    name: 'Ezra',
    specialty: 'VÉRITÉ & DÉCISIONS',
    tagline: 'Honnête et sans compromis, il n’édulcore rien.',
    bio: 'Je préfère une lecture qui dérange un peu à une réponse qui rassure sans rien dire. Si tu viens me voir, je vais chercher le point central de ta situation et je te dirai clairement ce que j’en comprends. Mon approche est franche, sans détour et sans fausse promesse. Quand quelque chose me paraît bloqué, ambigu ou au contraire en mouvement, je l’assume.',
    assetPath: 'assets/conseillers/ezra.webp',
    voicePath: 'vocaux/ezra_presentation.mp3',
  ),
  AdvisorInfo(
    name: 'Kaël',
    specialty: 'TRANSITIONS',
    tagline: 'Doux et progressif, il accompagne les transformations.',
    bio: 'Je travaille surtout sur les périodes où quelque chose est en train de changer : fin d’une relation, nouveau départ, décision importante ou impression d’être entre deux étapes. Mon approche est douce, mais pas floue. Je prends le temps de comprendre où tu en es avant de regarder ce qui semble s’ouvrir, se fermer ou demander encore du temps.',
    assetPath: 'assets/conseillers/kael.webp',
    voicePath: 'vocaux/kael_presentation.mp3',
  ),
  AdvisorInfo(
    name: 'Raphaël',
    specialty: 'RELATIONS',
    tagline: 'Empathique, il éclaire ce qui unit et ce qui bloque.',
    bio: 'Je m’intéresse aux liens entre les personnes : ce qui rapproche, ce qui éloigne, ce qui reste non dit et ce qui crée un blocage. Mon approche est empathique et attentive, sans éviter les points difficiles. Je cherche à comprendre la dynamique réelle de la relation avant de te donner ma lecture, pour que la réponse reste reliée à ce que tu vis.',
    assetPath: 'assets/conseillers/raphael.webp',
    voicePath: 'vocaux/raphael_presentation.mp3',
  ),
];

/// Section "Découvre nos conseillers" — carrousel horizontal des 10 conseillers.
/// Un tap sur une carte ouvre la fiche complète du conseiller.
class AdvisorsCarousel extends StatelessWidget {
  const AdvisorsCarousel({super.key, this.selectedAdvisorName});

  final String? selectedAdvisorName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            'Découvre nos conseillers',
            style: AuryelText.display(
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 248,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 28),
            itemCount: kAdvisors.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final advisor = kAdvisors[index];
              return _AdvisorCard(
                advisor: advisor,
                isSelected: advisor.name == selectedAdvisorName,
                selectedAdvisorName: selectedAdvisorName,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AdvisorCard extends StatelessWidget {
  const _AdvisorCard({
    required this.advisor,
    required this.isSelected,
    required this.selectedAdvisorName,
  });

  final AdvisorInfo advisor;
  final bool isSelected;
  final String? selectedAdvisorName;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AdvisorDetailScreen(
              advisor: advisor,
              selectedAdvisorName: selectedAdvisorName,
            ),
          ),
        ),
        child: Container(
          width: 168,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AuryelColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? AuryelColors.gold.withValues(alpha: 0.55)
                  : AuryelColors.warmBorder,
              width: 1,
            ),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 16,
                child: isSelected
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          gradient: AuryelColors.goldGradient,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'MON CONSEILLER',
                          style: AuryelText.body(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: AuryelColors.backgroundDeep,
                            letterSpacing: 0.5,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 6),
              Container(
                width: 56,
                height: 56,
                padding: const EdgeInsets.all(2.5),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AuryelColors.goldGradient,
                ),
                child: ClipOval(
                  child: Image.asset(advisor.assetPath, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                advisor.name,
                style: AuryelText.display(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                advisor.specialty,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AuryelText.body(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.gold,
                  letterSpacing: 0.7,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  advisor.tagline,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AuryelText.body(
                    fontSize: 10,
                    height: 1.28,
                    color: AuryelColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
