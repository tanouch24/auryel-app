import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../state/auryel_state.dart';
import '../theme/auryel_theme.dart';
import '../widgets/advisors_carousel.dart';
import 'advisor_detail_screen.dart';

/// UX-B §5-§6 — « Changer de conseiller ». Parcours des 10 conseillers dans
/// une LISTE verticale (jamais un simple mur de visages) : chacun avec photo,
/// prénom, spécialité et accroche. Un tap ouvre la fiche détaillée existante
/// ([AdvisorDetailScreen]) où le choix est confirmé.
class AdvisorChooserScreen extends StatelessWidget {
  const AdvisorChooserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final selectedName = AuryelStateScope.of(context).selectedAdvisor;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: PhosphorIcon(
                        PhosphorIconsThin.arrowLeft,
                        size: 22,
                        color: AuryelColors.textMuted,
                      ),
                      splashRadius: 20,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 4),
                child: Text(
                  'Changer de conseiller',
                  style: AuryelText.screenTitle(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
                child: Text(
                  'Ton nouveau conseiller t’accompagnera dès ta prochaine '
                  'consultation. Une consultation en cours n’est pas '
                  'interrompue.',
                  style: AuryelText.bodySecondary(),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  itemCount: kAdvisors.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final advisor = kAdvisors[index];
                    return _AdvisorRow(
                      advisor: advisor,
                      isCurrent: advisor.name == selectedName,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AdvisorDetailScreen(
                            advisor: advisor,
                            selectedAdvisorName: selectedName,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdvisorRow extends StatelessWidget {
  const _AdvisorRow({
    required this.advisor,
    required this.isCurrent,
    required this.onTap,
  });

  final AdvisorInfo advisor;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AuryelColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isCurrent
                  ? AuryelColors.gold.withValues(alpha: 0.55)
                  : AuryelColors.warmBorder,
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 60,
                padding: const EdgeInsets.all(2.5),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AuryelColors.goldGradient,
                ),
                child: ClipOval(
                  child: Image.asset(advisor.assetPath, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            advisor.name,
                            style: AuryelText.cardTitle(),
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              gradient: AuryelColors.goldGradient,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'ACTUEL',
                              style: AuryelText.body(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                                color: AuryelColors.backgroundDeep,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      advisor.specialty,
                      style: AuryelText.body(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.gold,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      advisor.tagline,
                      style: AuryelText.body(
                        fontSize: 12.5,
                        height: 1.35,
                        color: AuryelColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              PhosphorIcon(
                PhosphorIconsThin.caretRight,
                size: 18,
                color: AuryelColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
