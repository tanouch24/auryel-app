import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/advisor_audio.dart';
import '../state/auryel_state.dart';
import '../state/consultation_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/advisors_carousel.dart'
    show AdvisorInfo, advisorByGuideKey, advisorByName, kAdvisors;
import '../widgets/consultation_block.dart' show ConsultationState;
import '../widgets/main_nav_scope.dart';
import 'advisor_detail_screen.dart';
import 'chat_screen.dart';
import 'premium_screen.dart';

/// Onglet central « CONSULTATION » — feed vertical immersif des 10 conseillers
/// Auryel (un conseiller par page, portrait au centre, voix de présentation en
/// autoplay avec fondu). Aucune vidéo.
///
/// Règles clés :
///  - une consultation active est PRIORISÉE (bandeau « Reprendre ») et reste
///    toujours avec son conseiller de session — jamais rebasculée ;
///  - un seul lecteur audio, jamais deux voix en même temps ;
///  - autoplay coupé si l'utilisateur a coupé le son (préférence persistée), si
///    l'onglet n'est plus visible, ou si l'app passe en arrière-plan ;
///  - le temps disponible vient du serveur (`ConsultationController`), aucun
///    recalcul local.
class ConsultationScreen extends StatefulWidget {
  const ConsultationScreen({super.key, this.audioOverride});

  /// Test uniquement : lecteur audio injecté (aucun canal plateforme en test).
  final AdvisorAudio? audioOverride;

  @override
  State<ConsultationScreen> createState() => _ConsultationScreenState();
}

const String _kMutedKey = 'auryel.consultation.audio_muted.v1';

class _ConsultationScreenState extends State<ConsultationScreen>
    with WidgetsBindingObserver {
  final PageController _pages = PageController();
  late final AdvisorAudio _audio =
      widget.audioOverride ?? AudioPlayersAdvisorAudio();

  int _page = 0;
  bool _muted = false;
  bool _onThisTab = true;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    _audio.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final idx = MainNavScope.maybeOf(context)?.currentIndex;
    final onTab = idx == null || idx == kTabConsultation;
    if (onTab != _onThisTab) {
      _onThisTab = onTab;
      if (onTab) {
        _maybePlayCurrent();
      } else {
        _stopAudio();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stopAudio();
    } else if (_onThisTab) {
      _maybePlayCurrent();
    }
  }

  Future<void> _loadPrefs() async {
    var muted = false;
    try {
      final p = await SharedPreferences.getInstance();
      muted = p.getBool(_kMutedKey) ?? false;
    } catch (_) {
      /* défaut : son activé */
    }
    if (!mounted) return;
    setState(() => _muted = muted);
    if (!muted && _onThisTab) _maybePlayCurrent();
  }

  String? _voiceFor(int i) {
    if (i < 0 || i >= kAdvisors.length) return null;
    final path = kAdvisors[i].voicePath.trim();
    return path.isEmpty ? null : path;
  }

  Future<void> _stopAudio() => _audio.stop();

  Future<void> _maybePlayCurrent() async {
    if (_muted || !_onThisTab || !mounted) return;
    final path = _voiceFor(_page);
    if (path == null) return; // conseiller sans audio -> aucun autoplay
    await _audio.play(
      path,
      fadeIn: _reduceMotion ? Duration.zero : const Duration(milliseconds: 400),
    );
  }

  Future<void> _onPageChanged(int i) async {
    if (i == _page) return;
    setState(() => _page = i);
    await _stopAudio();
    await _maybePlayCurrent();
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    setState(() => _muted = next);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kMutedKey, next);
    } catch (_) {
      /* la préférence en mémoire reste correcte pour la session */
    }
    if (next) {
      await _stopAudio();
    } else {
      await _maybePlayCurrent();
    }
  }

  static ConsultationState _derive(ConsultationController c) {
    if (c.hasActiveSession) return ConsultationState.active;
    final q = c.quota;
    if (q?.firstFreeAvailable == true) return ConsultationState.firstFree;
    final t = c.time;
    if (t != null) {
      return t.hasTime
          ? ConsultationState.subscriberAvailable
          : ConsultationState.locked;
    }
    if (q == null) return ConsultationState.firstFree;
    if (q.isPremium && q.monthlyRemaining > 0) {
      return ConsultationState.subscriberAvailable;
    }
    if (q.earnedAvailable > 0) return ConsultationState.subscriberAvailable;
    return ConsultationState.locked;
  }

  Future<void> _openChat(AdvisorInfo advisor) async {
    await _stopAudio();
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ChatScreen(advisor: advisor)));
    if (mounted && _onThisTab) _maybePlayCurrent();
  }

  void _openPremium() {
    _stopAudio();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
  }

  Future<void> _startWith(AdvisorInfo advisor) async {
    final state = AuryelStateScope.of(context);
    if (advisor.name != state.selectedAdvisor) {
      await state.changeAdvisor(advisor.name, advisor.guideKey);
    }
    await _openChat(advisor);
  }

  Future<void> _choosePreferred(AdvisorInfo advisor) async {
    final state = AuryelStateScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await state.changeAdvisor(advisor.name, advisor.guideKey);
    if (!mounted) return;
    switch (outcome) {
      case AdvisorChangeOutcome.synced:
      case AdvisorChangeOutcome.localOnly:
      case AdvisorChangeOutcome.unchanged:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${advisor.name} sera ton conseiller à ta prochaine consultation.',
            ),
          ),
        );
      case AdvisorChangeOutcome.networkFailed:
        messenger.showSnackBar(
          const SnackBar(content: Text('Connexion impossible — réessaie.')),
        );
      case AdvisorChangeOutcome.unauthorized:
        messenger.showSnackBar(
          const SnackBar(content: Text('Ta session a expiré. Reconnecte-toi.')),
        );
    }
  }

  Future<void> _openDetail(AdvisorInfo advisor) async {
    final selectedName = AuryelStateScope.of(context).selectedAdvisor;
    await _stopAudio();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdvisorDetailScreen(
          advisor: advisor,
          selectedAdvisorName: selectedName,
        ),
      ),
    );
    if (mounted && _onThisTab) _maybePlayCurrent();
  }

  @override
  Widget build(BuildContext context) {
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    final consultation = ConsultationScope.maybeReadOf(context);
    final state = AuryelStateScope.of(context);

    final activeId = (consultation?.hasActiveSession ?? false)
        ? consultation!.active?.advisorId
        : null;
    final activeAdvisor = activeId == null ? null : advisorByGuideKey(activeId);
    final resumeAdvisor =
        activeAdvisor ??
        (consultation?.hasResumableConsultation ?? false
            ? advisorByName(state.selectedAdvisor ?? kAdvisors.first.name)
            : null);
    final timeLabel = consultation?.availableTimeLabel ?? '1 h offerte';
    final locked =
        consultation != null &&
        _derive(consultation) == ConsultationState.locked;

    return Container(
      decoration: const BoxDecoration(
        gradient: AuryelColors.backgroundGradient,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TopBar(
              timeLabel: timeLabel,
              muted: _muted,
              audioAvailable: _voiceFor(_page) != null,
              onToggleMute: _toggleMute,
            ),
            if (resumeAdvisor != null)
              _ActiveSessionBanner(
                advisor: resumeAdvisor,
                onResume: () => _openChat(resumeAdvisor),
              ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                scrollDirection: Axis.vertical,
                onPageChanged: _onPageChanged,
                itemCount: kAdvisors.length,
                itemBuilder: (context, i) {
                  final advisor = kAdvisors[i];
                  final isActiveThis =
                      activeId != null && activeId == advisor.guideKey;
                  final isActiveOther =
                      activeId != null && activeId != advisor.guideKey;

                  String primaryLabel;
                  VoidCallback? primaryTap;
                  if (isActiveThis) {
                    primaryLabel = 'Reprendre ma consultation';
                    primaryTap = () => _openChat(advisor);
                  } else if (isActiveOther) {
                    primaryLabel = 'Reprendre ma consultation';
                    primaryTap = resumeAdvisor != null
                        ? () => _openChat(resumeAdvisor)
                        : null;
                  } else if (locked) {
                    primaryLabel = 'S’abonner';
                    primaryTap = _openPremium;
                  } else {
                    primaryLabel = 'Consulter ${advisor.name}';
                    primaryTap = () => _startWith(advisor);
                  }

                  return _AdvisorPage(
                    advisor: advisor,
                    isCurrent: i == _page,
                    reduceMotion: _reduceMotion,
                    primaryLabel: primaryLabel,
                    onPrimary: primaryTap,
                    activeOtherNote: isActiveOther && resumeAdvisor != null
                        ? 'Ta consultation en cours reste avec '
                              '${resumeAdvisor.name}.'
                        : null,
                    onChooseNext: isActiveOther
                        ? () => _choosePreferred(advisor)
                        : null,
                    onDetail: () => _openDetail(advisor),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.timeLabel,
    required this.muted,
    required this.audioAvailable,
    required this.onToggleMute,
  });

  final String timeLabel;
  final bool muted;
  final bool audioAvailable;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 8, 8),
      child: Row(
        children: [
          Text(
            'Temps disponible : ',
            style: AuryelText.body(
              fontSize: 11.5,
              color: AuryelColors.textMuted,
            ),
          ),
          Expanded(
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
          Semantics(
            button: true,
            label: muted
                ? 'Activer le son des présentations'
                : 'Couper le son des présentations',
            child: IconButton(
              onPressed: audioAvailable ? onToggleMute : null,
              icon: PhosphorIcon(
                muted
                    ? PhosphorIconsRegular.speakerSlash
                    : PhosphorIconsRegular.speakerHigh,
                size: 20,
                color: audioAvailable
                    ? (muted ? AuryelColors.textMuted : AuryelColors.goldLight)
                    : AuryelColors.warmBorder,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveSessionBanner extends StatelessWidget {
  const _ActiveSessionBanner({required this.advisor, required this.onResume});

  final AdvisorInfo advisor;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AuryelColors.gold.withValues(alpha: 0.12),
        border: Border.all(
          color: AuryelColors.goldLight.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              advisor.assetPath,
              width: 38,
              height: 38,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(width: 38, height: 38),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Consultation en cours avec ${advisor.name}',
              style: AuryelText.body(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AuryelColors.textCream,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _MiniGoldButton(label: 'Reprendre ma consultation', onTap: onResume),
        ],
      ),
    );
  }
}

class _AdvisorPage extends StatelessWidget {
  const _AdvisorPage({
    required this.advisor,
    required this.isCurrent,
    required this.reduceMotion,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onDetail,
    this.activeOtherNote,
    this.onChooseNext,
  });

  final AdvisorInfo advisor;
  final bool isCurrent;
  final bool reduceMotion;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback onDetail;
  final String? activeOtherNote;
  final VoidCallback? onChooseNext;

  List<String> get _specialties => advisor.specialty
      .split(RegExp(r'\s*&\s*'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .take(4)
      .toList();

  @override
  Widget build(BuildContext context) {
    final anim = isCurrent ? 1.0 : 0.0;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Portrait — pièce centrale.
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 0.82,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        advisor.assetPath,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: AuryelColors.surface),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.center,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00000000), Color(0xCC120E17)],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 14,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              advisor.name,
                              style: AuryelText.display(
                                fontSize: 30,
                                fontWeight: FontWeight.w600,
                                color: AuryelColors.textCream,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              advisor.specialty,
                              style: AuryelText.body(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AuryelColors.goldLight,
                                letterSpacing: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            advisor.tagline,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AuryelText.body(
              fontSize: 13,
              height: 1.35,
              color: AuryelColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in _specialties)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AuryelColors.gold.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    s,
                    style: AuryelText.body(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AuryelColors.gold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          if (activeOtherNote != null) ...[
            const SizedBox(height: 8),
            Text(
              activeOtherNote!,
              textAlign: TextAlign.center,
              style: AuryelText.body(
                fontSize: 11,
                color: AuryelColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _MainGoldButton(label: primaryLabel, onTap: onPrimary),
          const SizedBox(height: 6),
          if (onChooseNext != null)
            TextButton(
              onPressed: onChooseNext,
              child: Text(
                'Choisir ${advisor.name} pour ma prochaine consultation',
                style: AuryelText.body(
                  fontSize: 11.5,
                  color: AuryelColors.textMuted,
                ),
              ),
            )
          else
            TextButton(
              onPressed: onDetail,
              child: Text(
                'Découvrir ${advisor.name}',
                style: AuryelText.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.goldLight,
                ),
              ),
            ),
        ],
      ),
    );

    if (reduceMotion) return content;
    return AnimatedOpacity(
      opacity: anim == 1.0 ? 1.0 : 0.55,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: AnimatedScale(
        scale: anim == 1.0 ? 1.0 : 0.97,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: content,
      ),
    );
  }
}

class _MainGoldButton extends StatelessWidget {
  const _MainGoldButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: double.infinity,
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
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: Text(
                    label,
                    style: AuryelText.body(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AuryelColors.backgroundDeep,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniGoldButton extends StatelessWidget {
  const _MiniGoldButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: AuryelColors.goldGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'Reprendre',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AuryelColors.backgroundDeep,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
