import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../api/wellbeing_api.dart';
import '../data/daily_share_tracker.dart';
import '../data/daily_thought.dart';
import '../data/share_reward_repository.dart';
import '../state/auth_controller.dart';
import '../state/consultation_controller.dart';
import '../theme/auryel_theme.dart';

/// Signature du partage natif — injectable pour les tests (aucun canal
/// plateforme en environnement de test). `imageBytes` = octets du WEBP du jour.
typedef ShareThoughtCallback = Future<void> Function({
  Uint8List? imageBytes,
  required String text,
});

Future<void> _defaultShare({
  Uint8List? imageBytes,
  required String text,
}) async {
  if (imageBytes != null && imageBytes.isNotEmpty) {
    // On partage le WEBP FINAL du pack (phrase + interprétation + design déjà
    // dessus). `XFile.fromData` matérialise lui-même un fichier temporaire côté
    // plateforme -> pas de conversion PNG, pas de RepaintBoundary.
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        files: [
          XFile.fromData(
            imageBytes,
            mimeType: 'image/webp',
            name: 'auryel-pensee-du-jour.webp',
          ),
        ],
      ),
    );
    return;
  }
  await SharePlus.instance.share(ShareParams(text: text));
}

/// Ouvre l'aperçu de LA publication du jour : un seul visuel (déjà généré),
/// un bouton « Partager » (feuille de partage native), le compteur « X / 30 ».
/// Aucune date, aucune variante, aucun poster généré à la volée.
Future<void> showDailyThoughtSheet(
  BuildContext context, {
  required DailyThought thought,
  ShareThoughtCallback? onShare,
  DailyShareTracker? tracker,
  AssetBundle? bundle,
  ShareRewardRepository? shareReward,
  VoidCallback? onRewardCredited,
  WellbeingApi? wellbeingApi,
}) {
  // Défaut PRODUCTION : la progression 30 jours devient serveur-autoritative
  // dès qu'un backend récompense est câblé (AuthScope.rewardsApi). Sinon,
  // `recordShare()` renvoie `null` et l'affichage retombe sur le cache local.
  final auth = AuthScope.maybeOf(context);
  final consultation = ConsultationScope.maybeReadOf(context);

  // PARCOURS BIEN-ÊTRE (J7) — OUVRIR cette feuille = « CONSULTER la Pensée du
  // jour ». Événement distinct du PARTAGE : on enregistre la mission `pensee`
  // (1 fois / jour côté serveur, idempotent). Fire-and-forget, toutes erreurs
  // absorbées : aucun impact sur l'affichage ni le partage. AUCUN lien avec la
  // récompense de partage J5.
  final wbApi = wellbeingApi ?? auth?.wellbeingApi;
  if (wbApi != null && auth != null) {
    () async {
      try {
        final token = await auth.currentToken();
        if (token != null && token.isNotEmpty) {
          await wbApi.recordMission(bearer: token, missionId: 'pensee');
        }
      } catch (_) {
        /* progression serveur non bloquante */
      }
    }();
  }
  final reward =
      shareReward ??
      (auth == null
          ? null
          : ShareRewardRepository(
              api: auth.rewardsApi,
              tokenProvider: auth.currentToken,
            ));
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DailyMessageSheet(
      thought: thought,
      onShare: onShare ?? _defaultShare,
      tracker: tracker ?? DailyShareTracker(),
      bundle: bundle,
      shareReward: reward,
      // Après un crédit serveur confirmé : on rafraîchit le portefeuille de
      // temps DEPUIS le serveur (jamais de +3600 local).
      onRewardCredited: onRewardCredited ?? consultation?.refresh,
    ),
  );
}

class DailyMessageSheet extends StatefulWidget {
  const DailyMessageSheet({
    super.key,
    required this.thought,
    required this.onShare,
    required this.tracker,
    this.bundle,
    this.shareReward,
    this.onRewardCredited,
  });

  final DailyThought thought;
  final ShareThoughtCallback onShare;
  final DailyShareTracker tracker;

  /// Test uniquement : bundle d'assets injecté (chargement du WEBP).
  final AssetBundle? bundle;

  /// Récompense 30 jours — source de vérité serveur. `null` = pas câblé
  /// (affichage sur cache local uniquement).
  final ShareRewardRepository? shareReward;

  /// Appelé UNE fois quand le serveur confirme `credited == true` — sert à
  /// rafraîchir le portefeuille de temps depuis le serveur.
  final VoidCallback? onRewardCredited;

  @override
  State<DailyMessageSheet> createState() => _DailyMessageSheetState();
}

class _DailyMessageSheetState extends State<DailyMessageSheet> {
  bool _sharing = false;
  int _sharedDays = 0;

  /// Progression SERVEUR (prévaut sur le cache local quand disponible).
  int? _serverCount;
  int _target = 30;
  bool _justCredited = false;

  int get _displayDays => _serverCount ?? _sharedDays;

  @override
  void initState() {
    super.initState();
    _loadCounter();
    _loadServerProgress();
  }

  Future<void> _loadCounter() async {
    try {
      final n = await widget.tracker.sharedDaysCount();
      if (mounted) setState(() => _sharedDays = n);
    } catch (_) {
      /* défaut : 0 */
    }
  }

  Future<void> _loadServerProgress() async {
    final progress = await widget.shareReward?.loadProgress();
    if (progress == null || !mounted) return;
    setState(() {
      _serverCount = progress.count;
      _target = progress.target;
    });
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      Uint8List? bytes;
      final asset = widget.thought.imageAsset;
      if (asset.isNotEmpty) {
        try {
          final data = await (widget.bundle ?? rootBundle).load(asset);
          bytes = data.buffer.asUint8List();
        } catch (_) {
          // Asset illisible -> on partage au moins le texte.
          bytes = null;
        }
      }
      // Pensée servie par le backend : pas d'asset embarqué -> partage texte
      // seul (l'image distante n'est pas re-téléchargée pour le partage).
      await widget.onShare(
        imageBytes: bytes,
        text: '${widget.thought.phrase}\n\n— Auryel',
      );
      // Cache local NON autoritaire (1 jour max / jour calendaire) — sert
      // seulement si le serveur est indisponible.
      await widget.tracker.recordShareAttempt();
      await _loadCounter();

      // Déclaration serveur du jour de partage. Le SERVEUR décide s'il compte
      // le jour et s'il crédite au palier. AUCUN crédit local.
      final progress = await widget.shareReward?.recordShare();
      if (progress != null && mounted) {
        setState(() {
          _serverCount = progress.count;
          _target = progress.target;
        });
        if (progress.credited) {
          setState(() => _justCredited = true);
          // Rafraîchit le portefeuille DEPUIS le serveur (pas de +3600 local).
          widget.onRewardCredited?.call();
        }
      }
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

              Text(
                'TA PUBLICATION DU JOUR',
                textAlign: TextAlign.center,
                style: AuryelText.body(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.gold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 14),

              // LE visuel final du jour (WEBP : phrase + interprétation + design).
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: media.size.height * 0.62,
                    maxWidth: 340,
                  ),
                  child: AspectRatio(
                    aspectRatio: 1080 / 1920,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: _PublicationImage(
                        thought: widget.thought,
                        bundle: widget.bundle,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),
              _GoldCta(label: 'Partager', loading: _sharing, onTap: _share),
              const SizedBox(height: 10),
              Text(
                'Partage avec l’application de ton choix. '
                '$_displayDays / $_target jours.',
                textAlign: TextAlign.center,
                style: AuryelText.body(
                  fontSize: 11.5,
                  color: AuryelColors.textMuted,
                ),
              ),
              if (_justCredited) ...[
                const SizedBox(height: 8),
                Text(
                  'Bravo ! 1 heure de consultation vient d’être ajoutée à ton '
                  'compte.',
                  textAlign: TextAlign.center,
                  style: AuryelText.body(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.goldLight,
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

/// Visuel de la publication du jour : asset embarqué (pack local) OU image
/// distante (`daily_publication.image_url` quand la pensée vient du backend).
/// Toute défaillance retombe sur un aplat sombre — jamais d'exception, jamais
/// d'écran vide.
class _PublicationImage extends StatelessWidget {
  const _PublicationImage({required this.thought, this.bundle});

  final DailyThought thought;
  final AssetBundle? bundle;

  @override
  Widget build(BuildContext context) {
    const fallback = ColoredBox(color: AuryelColors.backgroundDeep);
    if (thought.imageAsset.isNotEmpty) {
      return Image.asset(
        thought.imageAsset,
        bundle: bundle,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    final url = thought.imageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return fallback;
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
