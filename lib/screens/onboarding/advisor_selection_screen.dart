import 'package:flutter/material.dart';

import '../../state/auryel_state.dart';
import '../../theme/auryel_theme.dart';
import '../../widgets/advisors_carousel.dart';
import '../../widgets/onboarding_scaffold.dart';
import 'first_name_screen.dart';

/// Étape 1/5 — choix du conseiller. Réutilise le modèle `AdvisorInfo` et la
/// liste `kAdvisors` déjà utilisés par le carrousel de l'accueil et la fiche
/// conseiller — aucune donnée dupliquée.
class AdvisorSelectionScreen extends StatefulWidget {
  const AdvisorSelectionScreen({super.key});

  @override
  State<AdvisorSelectionScreen> createState() => _AdvisorSelectionScreenState();
}

class _AdvisorSelectionScreenState extends State<AdvisorSelectionScreen> {
  String? _selected;

  void _continue() {
    if (_selected == null) return;
    AuryelStateScope.of(context).selectAdvisor(_selected!);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const FirstNameScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 1,
      totalSteps: 5,
      showBack: false,
      title: 'Choisis ton conseiller',
      subtitle: 'Il t’accompagnera dans tes consultations.',
      ctaLabel: 'Continuer',
      ctaEnabled: _selected != null,
      onCta: _continue,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: kAdvisors.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        itemBuilder: (context, index) {
          final advisor = kAdvisors[index];
          final isSelected = advisor.name == _selected;
          return _SelectableAdvisorTile(
            advisor: advisor,
            isSelected: isSelected,
            onTap: () => setState(() => _selected = advisor.name),
          );
        },
      ),
    );
  }
}

class _SelectableAdvisorTile extends StatelessWidget {
  const _SelectableAdvisorTile({
    required this.advisor,
    required this.isSelected,
    required this.onTap,
  });

  final AdvisorInfo advisor;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? AuryelColors.surfaceLight
                : AuryelColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? AuryelColors.gold : AuryelColors.warmBorder,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isSelected
                      ? AuryelColors.goldGradient
                      : LinearGradient(
                          colors: [
                            AuryelColors.gold.withValues(alpha: 0.5),
                            AuryelColors.goldDark.withValues(alpha: 0.5),
                          ],
                        ),
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
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.gold,
                  letterSpacing: 0.6,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
