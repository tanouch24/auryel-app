import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/advisor_audio.dart';
import '../theme/auryel_theme.dart';
import '../widgets/advisors_carousel.dart' show AdvisorInfo, kAdvisors;

/// Sélecteur de conseiller — réutilise le feed vertical immersif des 10
/// conseillers Auryel (un conseiller par page, portrait au centre, voix de
/// présentation en autoplay avec fondu). Il n'est PLUS l'écran principal de
/// l'onglet Consultation : il s'ouvre depuis « Choisir un conseiller », «
/// Demander un autre avis » ou le tirage « En parler ».
///
/// Il ne fait qu'UNE chose : renvoyer (`Navigator.pop`) le [AdvisorInfo] choisi.
/// Il n'appelle JAMAIS `changeAdvisor`, ne PATCH aucun profil, n'ouvre aucune
/// consultation — l'appelant décide (fil existant à reprendre vs `openAdvisor`).
class AdvisorSelectorScreen extends StatefulWidget {
  const AdvisorSelectorScreen({
    super.key,
    this.existingAdvisorIds = const {},
    this.title = 'Choisis un conseiller',
    this.audioOverride,
  });

  /// Clés backend (`guideKey`) des conseillers pour lesquels un fil existe
  /// déjà : la carte propose alors « Reprendre » au lieu de « Demander un avis ».
  final Set<String> existingAdvisorIds;

  /// Titre affiché en tête (ex. « Avec qui veux-tu en parler ? » depuis le
  /// tirage).
  final String title;

  /// Test uniquement : lecteur audio injecté (aucun canal plateforme en test).
  final AdvisorAudio? audioOverride;

  @override
  State<AdvisorSelectorScreen> createState() => _AdvisorSelectorScreenState();
}

const String _kMutedKey = 'auryel.consultation.audio_muted.v1';

class _AdvisorSelectorScreenState extends State<AdvisorSelectorScreen>
    with WidgetsBindingObserver {
  final PageController _pages = PageController();
  late final AdvisorAudio _audio =
      widget.audioOverride ?? AudioPlayersAdvisorAudio();

  int _page = 0;
  bool _muted = false;
  bool _reduceMotion = false;

  /// Indice « il y a d'autres conseillers plus bas » — PAR FICHE : chaque
  /// conseiller (pas seulement le premier) doit montrer l'indice à sa
  /// PREMIÈRE apparition. Il ne disparaît, POUR CETTE fiche, qu'une fois que
  /// l'utilisateur a réellement défilé DEPUIS elle (page suivante/
  /// précédente atteinte). Revenir sur une fiche déjà quittée une fois ne
  /// réaffiche pas l'indice (l'utilisateur a déjà prouvé qu'il sait défiler).
  final Set<int> _cueDismissedFor = {};

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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stopAudio();
    } else {
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
    if (!muted) _maybePlayCurrent();
  }

  String? _voiceFor(int i) {
    if (i < 0 || i >= kAdvisors.length) return null;
    final path = kAdvisors[i].voicePath.trim();
    return path.isEmpty ? null : path;
  }

  Future<void> _stopAudio() async {
    try {
      await _audio.stop();
    } catch (_) {
      /* un échec du lecteur ne doit jamais bloquer la navigation */
    }
  }

  Future<void> _maybePlayCurrent() async {
    if (_muted || !mounted) return;
    final path = _voiceFor(_page);
    if (path == null) return;
    try {
      await _audio.play(
        path,
        fadeIn: _reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 400),
      );
    } catch (_) {
      /* voix de présentation indisponible : on continue sans son */
    }
  }

  Future<void> _onPageChanged(int i) async {
    if (i == _page) return;
    final left = _page;
    setState(() {
      _page = i;
      // L'utilisateur vient de défiler RÉELLEMENT DEPUIS `left` : son indice
      // ne lui sert plus, pour CETTE fiche précise. La fiche `i` qu'il vient
      // d'atteindre, elle, montrera le sien si c'est sa toute première fois.
      _cueDismissedFor.add(left);
    });
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

  Future<void> _pick(AdvisorInfo advisor) async {
    final navigator = Navigator.of(context);
    await _stopAudio();
    navigator.pop(advisor);
  }

  @override
  Widget build(BuildContext context) {
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _TopBar(
                title: widget.title,
                muted: _muted,
                audioAvailable: _voiceFor(_page) != null,
                onBack: () {
                  _stopAudio();
                  Navigator.of(context).maybePop();
                },
                onToggleMute: _toggleMute,
              ),
              Expanded(
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: _pages,
                      scrollDirection: Axis.vertical,
                      onPageChanged: _onPageChanged,
                      itemCount: kAdvisors.length,
                      itemBuilder: (context, i) {
                        final advisor = kAdvisors[i];
                        final known = widget.existingAdvisorIds.contains(
                          advisor.guideKey,
                        );
                        return _AdvisorPage(
                          advisor: advisor,
                          isCurrent: i == _page,
                          reduceMotion: _reduceMotion,
                          alreadyConsulted: known,
                          primaryLabel: known ? 'Reprendre' : 'Parler',
                          onPrimary: () => _pick(advisor),
                          // CORRECTIF UX FINAL — l'indice apparaît pour CHAQUE
                          // fiche (pas uniquement la 1re/Luna) à sa première
                          // apparition, et seulement s'il reste un conseiller
                          // en dessous. Il s'efface, PAR FICHE, dès que
                          // l'utilisateur a réellement défilé depuis elle.
                          showScrollCue:
                              i < kAdvisors.length - 1 &&
                              !_cueDismissedFor.contains(i),
                        );
                      },
                    ),
                    // Fade de CONTINUATION en bas — suggère qu'il y a une suite.
                    // Même règle par fiche que l'indice ci-dessus. Ne capte
                    // aucun tap.
                    if (_page < kAdvisors.length - 1 &&
                        !_cueDismissedFor.contains(_page))
                      const Positioned(
                        key: Key('advisor-scroll-fade'),
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 84,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x00120E17), Color(0xC8120E17)],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.muted,
    required this.audioAvailable,
    required this.onBack,
    required this.onToggleMute,
  });

  final String title;
  final bool muted;
  final bool audioAvailable;
  final VoidCallback onBack;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Retour',
            icon: const PhosphorIcon(
              PhosphorIconsRegular.arrowLeft,
              size: 20,
              color: AuryelColors.textMuted,
            ),
          ),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: AuryelText.display(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AuryelColors.textCream,
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

class _AdvisorPage extends StatelessWidget {
  const _AdvisorPage({
    required this.advisor,
    required this.isCurrent,
    required this.reduceMotion,
    required this.alreadyConsulted,
    required this.primaryLabel,
    required this.onPrimary,
    this.showScrollCue = false,
  });

  final AdvisorInfo advisor;
  final bool isCurrent;
  final bool reduceMotion;
  final bool alreadyConsulted;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final bool showScrollCue;

  List<String> get _specialties => advisor.specialty
      .split(RegExp(r'\s*&\s*'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .take(4)
      .toList();

  @override
  Widget build(BuildContext context) {
    final anim = isCurrent ? 1.0 : 0.0;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // Le portrait est PLAFONNÉ : la description, les tags et le CTA restent
    // toujours visibles sans défiler, même sur un petit écran Android. Il peut
    // aussi rétrécir si la place manque.
    final portraitMaxH = (MediaQuery.sizeOf(context).height * 0.44).clamp(
      200.0,
      380.0,
    );
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: portraitMaxH),
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
                              if (alreadyConsulted)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: AuryelColors.goldGradient,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'DÉJÀ CONSULTÉ',
                                    style: AuryelText.body(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      color: AuryelColors.backgroundDeep,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
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
          ),
          const SizedBox(height: 12),
          Text(
            advisor.tagline,
            textAlign: TextAlign.center,
            maxLines: 2,
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
          // Indice « d'autres conseillers plus bas » : discret, entre les tags
          // et le CTA (ne masque jamais le portrait, ne concurrence jamais le
          // CTA). `SizedBox.shrink()` quand masqué -> aucun impact de mise en
          // page. Disparaît définitivement au 1er défilement.
          _ScrollCue(visible: showScrollCue, reduceMotion: reduceMotion),
          const SizedBox(height: 12),
          // Le CTA n'est jamais masqué par la barre système Android : la
          // SafeArea racine ne réserve pas le bas (feed vertical) -> on ajoute
          // ici l'inset système + une marge minimale.
          Padding(
            padding: EdgeInsets.only(bottom: bottomInset + 6),
            child: _MainGoldButton(
              label: '$primaryLabel avec ${advisor.name}',
              onTap: onPrimary,
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

/// Indice de défilement vertical — libellé court + chevron bas avec un très
/// léger va-et-vient. Purement décoratif (`IgnorePointer`). Rendu nul quand
/// masqué : aucun impact sur la mise en page, y compris petits écrans.
class _ScrollCue extends StatefulWidget {
  const _ScrollCue({required this.visible, required this.reduceMotion});

  final bool visible;
  final bool reduceMotion;

  @override
  State<_ScrollCue> createState() => _ScrollCueState();
}

class _ScrollCueState extends State<_ScrollCue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  void _startBob() {
    if (!widget.visible || widget.reduceMotion || _bob.isAnimating) return;
    // Va-et-vient FINI (plusieurs allers-retours bien perceptibles puis repos)
    // — jamais d'animation infinie, pour ne pas bloquer pumpAndSettle.
    _bob.repeat(reverse: true, count: 12);
  }

  @override
  void initState() {
    super.initState();
    _startBob();
  }

  @override
  void didUpdateWidget(_ScrollCue old) {
    super.didUpdateWidget(old);
    if (!old.visible && widget.visible) _startBob();
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    // Flèche unique, nettement plus visible qu'un double chevron discret —
    // « suffisamment grande » sans devenir un gros effet décoratif.
    Widget arrow = const PhosphorIcon(
      PhosphorIconsBold.arrowDown,
      size: 24,
      color: AuryelColors.goldLight,
    );
    if (!widget.reduceMotion) {
      arrow = AnimatedBuilder(
        animation: _bob,
        child: arrow,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, (_bob.value * 6) - 1),
          child: child,
        ),
      );
    }
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Semantics(
          label: 'Fais défiler pour découvrir les autres conseillers',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              arrow,
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      colors: [
                        AuryelColors.gold.withValues(alpha: 0.22),
                        AuryelColors.gold.withValues(alpha: 0.08),
                      ],
                    ),
                    border: Border.all(
                      color: AuryelColors.goldLight.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Text(
                    'Découvrir les autres conseillers',
                    maxLines: 1,
                    style: AuryelText.body(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AuryelColors.goldLight,
                      letterSpacing: 0.4,
                    ),
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
