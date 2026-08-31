import 'package:flutter/material.dart';

import '../../state/auryel_state.dart';
import '../../theme/auryel_theme.dart';
import '../../widgets/advisors_carousel.dart';
import '../../widgets/onboarding_scaffold.dart';
import 'account_creation_screen.dart';

/// Étape 4/5 — choix du conseiller, APRÈS le profil (prénom, date, « parle-moi
/// de toi »). Chaque conseiller est présenté avec photo + prénom + spécialité
/// + accroche pour être compréhensible AVANT sélection — jamais une simple
/// série de visages. Réutilise `AdvisorInfo` / `kAdvisors` (aucune donnée
/// dupliquée). Le choix alimente `AuryelState.selectedAdvisor` ; la synchro
/// backend a lieu plus loin dans le flux (inchangée).
class AdvisorSelectionScreen extends StatefulWidget {
  const AdvisorSelectionScreen({super.key});

  @override
  State<AdvisorSelectionScreen> createState() => _AdvisorSelectionScreenState();
}

class _AdvisorSelectionScreenState extends State<AdvisorSelectionScreen> {
  String? _selected;
  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    // Conserver un conseiller déjà choisi (retour arrière / reprise).
    final existing = AuryelStateScope.of(context).selectedAdvisor;
    if (advisorByNameOrNull(existing) != null) {
      _selected = existing;
    }
  }

  void _continue() {
    if (_selected == null) return;
    AuryelStateScope.of(context).selectAdvisor(_selected!);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AccountCreationScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 4,
      totalSteps: 5,
      title: 'Choisis ton conseiller',
      subtitle: 'Il t’accompagnera dans tes consultations. Tu pourras en '
          'changer plus tard.',
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
          childAspectRatio: 0.60,
        ),
        itemBuilder: (context, index) {
          final advisor = kAdvisors[index];
          return _SelectableAdvisorTile(
            advisor: advisor,
            isSelected: advisor.name == _selected,
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
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
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
                width: 58,
                height: 58,
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
              const SizedBox(height: 3),
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
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  advisor.tagline,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: AuryelText.body(
                    fontSize: 10,
                    height: 1.3,
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
