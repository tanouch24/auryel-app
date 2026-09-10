import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../api/api_client.dart';
import '../data/advisor_audio.dart';
import '../data/consultation.dart';
import '../state/auth_controller.dart';
import '../state/consultation_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/advisors_carousel.dart' show AdvisorInfo, advisorByGuideKey;
import '../widgets/main_nav_scope.dart';
import 'adult_gate.dart';
import 'advisor_selector_screen.dart';
import 'chat_screen.dart';
import 'onboarding/email_auth_screen.dart';

/// Onglet central « CONSULTATION » — J6-F2.
///
/// Contenu principal : la LISTE des discussions en cours (une par conseiller).
/// L'utilisateur revient toujours ici et choisit lui-même le fil à reprendre.
/// Il N'Y A PAS de conseiller référent : `AuryelState.selectedAdvisor` ne
/// détermine plus aucun fil, et aucune action de cet écran n'appelle
/// `changeAdvisor` / ne PATCH le profil.
///
///  - au chargement (et à chaque retour sur l'onglet / retour du chat) :
///    `ConsultationController.refreshConsultations()` ;
///  - liste vide -> état propre + CTA « Choisir un conseiller » ;
///  - liste non vide -> cartes + CTA permanent « Demander un autre avis » ;
///  - tap sur une carte -> `ChatScreen(consultationId, advisor)` EXACTS. Aucun
///    repli silencieux : conseiller inconnu -> erreur utilisateur contrôlée ;
///  - le temps disponible vient du serveur (`ConsultationController`), aucun
///    recalcul local.
class ConsultationScreen extends StatefulWidget {
  const ConsultationScreen({super.key, this.audioOverride});

  /// Transmis au sélecteur de conseillers (aucun canal plateforme en test).
  final AdvisorAudio? audioOverride;

  @override
  State<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends State<ConsultationScreen> {
  bool _refreshedOnce = false;
  int? _lastTabIndex;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `IndexedStack` garde l'onglet monté : on rafraîchit la LISTE chaque fois
    // qu'il (re)devient visible — l'aperçu / l'activité reflètent le dernier
    // état sans rouvrir aucun chat.
    final idx = MainNavScope.maybeOf(context)?.currentIndex;
    if (idx != null && idx != _lastTabIndex) {
      final wasElsewhere = _lastTabIndex != null && _lastTabIndex != idx;
      _lastTabIndex = idx;
      if (idx == kTabConsultation && (wasElsewhere || !_refreshedOnce)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
      }
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    _refreshedOnce = true;
    await ConsultationScope.maybeReadOf(context)?.refreshConsultations();
  }

  ConsultationController? get _controller =>
      ConsultationScope.maybeReadOf(context);

  Future<void> _openThread(ConsultationSummaryDto summary) async {
    final advisor = advisorByGuideKey(summary.advisorId);
    if (advisor == null) {
      // Aucun repli vers Séléna / kAdvisors.first : on n'ouvre pas un mauvais
      // conseiller. Erreur utilisateur contrôlée.
      _snack('Cette consultation est momentanément indisponible.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(consultationId: summary.id, advisor: advisor),
      ),
    );
    // Retour du chat -> on revient sur la LISTE et on rafraîchit l'aperçu.
    await _refresh();
  }

  Future<void> _chooseAdvisor() async {
    if (_busy) return;
    final controller = _controller;
    final navigator = Navigator.of(context);
    final existing = <String, ConsultationSummaryDto>{
      for (final c
          in controller?.consultations ?? const <ConsultationSummaryDto>[])
        c.advisorId: c,
    };

    final picked = await navigator.push<AdvisorInfo>(
      MaterialPageRoute(
        builder: (_) => AdvisorSelectorScreen(
          existingAdvisorIds: existing.keys.toSet(),
          audioOverride: widget.audioOverride,
        ),
      ),
    );
    if (picked == null || !mounted) return;

    // Fil déjà existant pour ce conseiller -> on rouvre CE fil (jamais un
    // nouveau, jamais `changeAdvisor`).
    final known = existing[picked.guideKey];
    if (known != null) {
      await _openThread(known);
      return;
    }
    if (controller == null) return;

    // Nouveau conseiller -> `openAdvisor` (POST /open) puis ChatScreen sur le
    // fil renvoyé. Aucun PATCH profil, aucun `changeAdvisor`.
    setState(() => _busy = true);
    try {
      final dto = await controller.openAdvisor(picked.guideKey);
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(consultationId: dto.id, advisor: picked),
        ),
      );
      await _refresh();
    } on ApiUnauthorizedException {
      if (!mounted) return;
      setState(() => _busy = false);
      await AuthScope.of(context).invalidateSession();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
        (route) => false,
      );
    } on ApiForbiddenException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final code = e.code ?? e.body['error']?.toString();
      if (code == 'age_verification_required' || code == 'adult_required') {
        // 403 âge : jamais « réessaie ». On réutilise AdultGate (autorité
        // serveur forcée) qui route vers `needsDob` ou l'écran bloqué.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const AdultGate(forceServerCheck: true),
          ),
          (route) => false,
        );
      } else {
        _snack('Connexion impossible — réessaie.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Connexion impossible — réessaie.');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Container(
      decoration: const BoxDecoration(
        gradient: AuryelColors.backgroundGradient,
      ),
      child: SafeArea(
        bottom: false,
        child: controller == null
            ? _Body(
                controller: null,
                onChoose: _chooseAdvisor,
                onOpen: _openThread,
                busy: _busy,
              )
            : ListenableBuilder(
                listenable: controller,
                builder: (context, _) => _Body(
                  controller: controller,
                  onChoose: _chooseAdvisor,
                  onOpen: _openThread,
                  busy: _busy,
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({
    required this.controller,
    required this.onChoose,
    required this.onOpen,
    required this.busy,
  });

  final ConsultationController? controller;
  final VoidCallback onChoose;
  final ValueChanged<ConsultationSummaryDto> onOpen;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final consultations = c?.consultations ?? const <ConsultationSummaryDto>[];
    final loading = (c?.consultationsLoading ?? false) && consultations.isEmpty;
    final timeLabel = c?.availableTimeLabel ?? '1 h offerte';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
          child: Text(
            'Consultations en cours',
            style: AuryelText.display(
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Row(
            children: [
              Text(
                'Temps disponible : ',
                style: AuryelText.body(
                  fontSize: 11.5,
                  color: AuryelColors.textMuted,
                ),
              ),
              Flexible(
                child: Text(
                  timeLabel,
                  overflow: TextOverflow.ellipsis,
                  style: AuryelText.body(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AuryelColors.goldLight,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AuryelColors.gold,
                    ),
                  ),
                )
              : consultations.isEmpty
              ? _EmptyState(onChoose: busy ? null : onChoose)
              : _ConsultationList(
                  consultations: consultations,
                  onOpen: onOpen,
                  onAskAnother: busy ? null : onChoose,
                ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onChoose});

  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PhosphorIcon(
              PhosphorIconsThin.chatsCircle,
              size: 44,
              color: AuryelColors.goldLight,
            ),
            const SizedBox(height: 16),
            Text(
              'Tu n’as pas encore de consultation en cours.',
              textAlign: TextAlign.center,
              style: AuryelText.body(
                fontSize: 14,
                height: 1.4,
                color: AuryelColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            _GoldButton(label: 'Choisir un conseiller', onTap: onChoose),
          ],
        ),
      ),
    );
  }
}

class _ConsultationList extends StatelessWidget {
  const _ConsultationList({
    required this.consultations,
    required this.onOpen,
    required this.onAskAnother,
  });

  final List<ConsultationSummaryDto> consultations;
  final ValueChanged<ConsultationSummaryDto> onOpen;
  final VoidCallback? onAskAnother;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        for (final summary in consultations)
          _ConsultationCard(
            summary: summary,
            advisor: advisorByGuideKey(summary.advisorId),
            onTap: () => onOpen(summary),
          ),
        const SizedBox(height: 8),
        _OutlineButton(label: 'Demander un autre avis', onTap: onAskAnother),
      ],
    );
  }
}

class _ConsultationCard extends StatelessWidget {
  const _ConsultationCard({
    required this.summary,
    required this.advisor,
    required this.onTap,
  });

  final ConsultationSummaryDto summary;
  final AdvisorInfo? advisor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = advisor?.name ?? 'Conseiller';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: 'Reprendre la consultation avec $name',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AuryelColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AuryelColors.warmBorder, width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AuryelColors.goldGradient,
                    ),
                    child: ClipOval(
                      child: advisor == null
                          ? const ColoredBox(color: AuryelColors.surface)
                          : Image.asset(
                              advisor!.assetPath,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const ColoredBox(color: AuryelColors.surface),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AuryelText.display(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (summary.windowActive) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: AuryelColors.gold.withValues(
                                    alpha: 0.14,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AuryelColors.goldLight.withValues(
                                      alpha: 0.55,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'En cours',
                                  style: AuryelText.body(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AuryelColors.goldLight,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          summary.preview ?? 'Reprends la conversation.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
                  const PhosphorIcon(
                    PhosphorIconsRegular.caretRight,
                    size: 16,
                    color: AuryelColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoldButton extends StatelessWidget {
  const _GoldButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: AuryelColors.goldGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              child: Text(
                label,
                style: AuryelText.body(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AuryelColors.backgroundDeep,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AuryelColors.gold.withValues(alpha: 0.55),
              ),
            ),
            child: Text(
              label,
              style: AuryelText.body(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AuryelColors.goldLight,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
