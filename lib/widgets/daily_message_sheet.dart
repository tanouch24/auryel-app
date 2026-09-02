import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../data/daily_like_store.dart';
import '../data/daily_message.dart';
import '../data/daily_share_tracker.dart';
import '../theme/auryel_theme.dart';
import 'daily_message_poster.dart';

/// Signature du partage natif — injectable pour les tests (aucun canal
/// plateforme en environnement de test).
typedef ShareCallback = Future<void> Function(
    {Uint8List? imagePng, required String text});

/// Signature de la capture de l'affiche en PNG, pour la variante d'index donné —
/// injectable pour les tests (`RenderRepaintBoundary.toImage()` a besoin du
/// vrai pipeline de rendu).
typedef PosterCapture = Future<Uint8List?> Function(int variantIndex);

/// Nombre de variantes de publication générées localement (B8.3 §3-C).
const int kPublicationVariantCount = 3;

Future<void> _defaultShare({Uint8List? imagePng, required String text}) async {
  if (imagePng != null && imagePng.isNotEmpty) {
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        files: [
          XFile.fromData(
            imagePng,
            mimeType: 'image/png',
            name: 'auryel-message-du-jour.png',
          ),
        ],
      ),
    );
    return;
  }
  await SharePlus.instance.share(ShareParams(text: text));
}

/// Ouvre la feuille de détail du message du jour (retour, phrase, interprétation,
/// « j'aime », génération de 3 variantes de publication, partage natif).
Future<void> showDailyMessageSheet(
  BuildContext context, {
  DailyMessage message = DailyMessage.today,
  ShareCallback? onShare,
  DailyShareTracker? tracker,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DailyMessageSheet(
      message: message,
      onShare: onShare ?? _defaultShare,
      tracker: tracker ?? DailyShareTracker(),
    ),
  );
}

class DailyMessageSheet extends StatefulWidget {
  const DailyMessageSheet({
    super.key,
    required this.message,
    required this.onShare,
    required this.tracker,
    this.captureOverride,
    this.likeStore,
  });

  final DailyMessage message;
  final ShareCallback onShare;
  final DailyShareTracker tracker;

  /// Test uniquement : remplace la capture PNG de la variante d'index donné.
  final PosterCapture? captureOverride;

  /// Test uniquement : store « j'aime » injecté.
  final DailyLikeStore? likeStore;

  @override
  State<DailyMessageSheet> createState() => _DailyMessageSheetState();
}

class _DailyMessageSheetState extends State<DailyMessageSheet> {
  late final DailyLikeStore _likeStore = widget.likeStore ?? DailyLikeStore();
  final List<GlobalKey> _variantKeys =
      List.generate(kPublicationVariantCount, (_) => GlobalKey());
  final ScrollController _carousel = ScrollController();

  bool _generated = false;
  int _selected = 0;
  bool _sharing = false;
  bool _liked = false;

  @override
  void initState() {
    super.initState();
    _loadLike();
  }

  @override
  void dispose() {
    _carousel.dispose();
    super.dispose();
  }

  void _onCarouselScroll(double viewportW) {
    if (viewportW <= 0 || !_carousel.hasClients) return;
    final i = (_carousel.offset / viewportW)
        .round()
        .clamp(0, kPublicationVariantCount - 1);
    if (i != _selected) setState(() => _selected = i);
  }

  Future<void> _loadLike() async {
    try {
      final v = await _likeStore.isLikedToday();
      if (mounted) setState(() => _liked = v);
    } catch (_) {/* défaut : non aimé */}
  }

  Future<void> _toggleLike() async {
    setState(() => _liked = !_liked);
    try {
      final v = await _likeStore.toggleToday();
      if (mounted && v != _liked) setState(() => _liked = v);
    } catch (_) {/* on garde l'état optimiste */}
  }

  void _generate() {
    if (_generated) return;
    setState(() => _generated = true);
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final png = widget.captureOverride != null
          ? await widget.captureOverride!(_selected)
          : await DailyMessagePoster.capturePng(_variantKeys[_selected]);
      await widget.onShare(
        imagePng: png,
        text: '${widget.message.text}\n\n— Auryel',
      );
      // B8.1 : on COMPTE seulement (1 jour max / jour) — accroche B10, aucune
      // récompense ici.
      await widget.tracker.recordShareAttempt();
    } catch (_) {
      // Le partage ne doit jamais faire planter l'écran.
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxH = media.size.height * 0.94;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        gradient: AuryelColors.backgroundGradient,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: AuryelColors.warmBorder, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 20 + media.padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1) barre de fermeture : poignée + bouton retour clair.
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AuryelColors.textMuted.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: _CloseButton(
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              const SizedBox(height: 4),

              // 2) date + phrase du jour
              Text(
                widget.message.dateLabel,
                textAlign: TextAlign.center,
                style: AuryelText.body(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AuryelColors.textMuted,
                  letterSpacing: 2.4,
                ),
              ),
              const SizedBox(height: 14),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: AuryelText.display(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    height: 1.34,
                  ),
                  children: [
                    TextSpan(text: widget.message.leadText),
                    TextSpan(
                      text: widget.message.accentText,
                      style: AuryelText.display(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                        color: AuryelColors.goldLight,
                        height: 1.34,
                      ),
                    ),
                  ],
                ),
              ),

              // 3) interprétation
              const SizedBox(height: 22),
              Text(
                'L’INTERPRÉTATION',
                textAlign: TextAlign.center,
                style: AuryelText.body(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.gold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.message.interpretation,
                style: AuryelText.body(
                  fontSize: 14,
                  height: 1.55,
                  color: AuryelColors.textSecondary,
                ),
              ),

              // 4) « J'aime »  + 5) « Générer la publication »
              const SizedBox(height: 20),
              Center(child: _LikeButton(liked: _liked, onTap: _toggleLike)),
              const SizedBox(height: 14),
              _GoldCta(
                label: 'Générer la publication',
                loading: false,
                onTap: _generate,
              ),

              // 6) publications générées + 7) relance + 8) partage
              if (_generated) ...[
                const SizedBox(height: 20),
                Text(
                  'CHOISIS TA PUBLICATION',
                  textAlign: TextAlign.center,
                  style: AuryelText.body(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.gold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 320,
                  // Carrousel horizontal NON paresseux (SingleChildScrollView) :
                  // les 3 variantes restent montées -> chaque RepaintBoundary est
                  // capturable même hors écran. Snapping page par page.
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final vw = c.maxWidth;
                      return NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          _onCarouselScroll(vw);
                          return false;
                        },
                        child: SingleChildScrollView(
                          controller: _carousel,
                          scrollDirection: Axis.horizontal,
                          physics: const PageScrollPhysics(),
                          child: Row(
                            children: [
                              for (var i = 0;
                                  i < kPublicationVariantCount;
                                  i++)
                                SizedBox(
                                  width: vw,
                                  child: Center(
                                    child: AnimatedScale(
                                      duration:
                                          const Duration(milliseconds: 160),
                                      scale: i == _selected ? 1.0 : 0.9,
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                            maxWidth: 190),
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                              color: i == _selected
                                                  ? AuryelColors.goldLight
                                                  : AuryelColors.warmBorder,
                                              width: i == _selected ? 2 : 1,
                                            ),
                                          ),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            child: DailyMessagePoster(
                                              message: widget.message,
                                              variant:
                                                  PosterVariant.values[i],
                                              boundaryKey: _variantKeys[i],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < kPublicationVariantCount; i++)
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _selected
                              ? AuryelColors.goldLight
                              : AuryelColors.textMuted.withValues(alpha: 0.4),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Ce message te fait penser à quelqu’un ?',
                  textAlign: TextAlign.center,
                  style: AuryelText.body(
                    fontSize: 13,
                    color: AuryelColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                _GoldCta(
                  label: 'Partager',
                  loading: _sharing,
                  onTap: _share,
                ),
                const SizedBox(height: 8),
                Text(
                  'On partage la variante affichée — tu choisis l’application.',
                  textAlign: TextAlign.center,
                  style: AuryelText.body(
                    fontSize: 11.5,
                    color: AuryelColors.textMuted,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  '3 variantes d’affiche, prêtes à partager.',
                  textAlign: TextAlign.center,
                  style: AuryelText.body(
                    fontSize: 11.5,
                    color: AuryelColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                PhosphorIconsRegular.x,
                size: 16,
                color: AuryelColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                'Fermer',
                style: AuryelText.body(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: AuryelColors.textMuted,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({required this.liked, required this.onTap});

  final bool liked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: liked
                  ? AuryelColors.goldLight
                  : AuryelColors.gold.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                liked ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                size: 16,
                color: AuryelColors.goldLight,
              ),
              const SizedBox(width: 8),
              Text(
                liked ? 'Aimé' : 'J’aime',
                style: AuryelText.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.goldLight,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoldCta extends StatelessWidget {
  const _GoldCta({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: AuryelColors.goldGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: loading ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(
                            AuryelColors.backgroundDeep,
                          ),
                        ),
                      )
                    : Text(
                        label,
                        style: AuryelText.body(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AuryelColors.backgroundDeep,
                          letterSpacing: 0.3,
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
