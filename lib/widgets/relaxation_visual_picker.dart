import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../data/relaxation_video.dart';
import '../theme/auryel_theme.dart';

/// Résultat du sélecteur de visuel : soit « revenir à l'automatique »
/// ([RelaxationVisualChoice.random]), soit un visuel précis
/// ([RelaxationVisualChoice.video]).
class RelaxationVisualChoice {
  const RelaxationVisualChoice._(this.isRandom, this.video);

  factory RelaxationVisualChoice.random() =>
      const RelaxationVisualChoice._(true, null);
  factory RelaxationVisualChoice.video(RelaxationVideo v) =>
      RelaxationVisualChoice._(false, v);

  final bool isRandom;
  final RelaxationVideo? video;
}

/// Détecte un titre « technique » (nom de fichier de banque d'images) qu'on ne
/// doit JAMAIS montrer à l'utilisateur : `relaxation-11210466`,
/// `11210466-hd_1080_1920_30fps`, un slug brut, etc.
final RegExp _technicalTitle = RegExp(
  r'^(relaxation[-_ ]?\d+|v[-_]\d+|\d{5,})([-_ ].*)?$|_\d{3,}_\d{3,}',
  caseSensitive: false,
);

/// Libellé utilisateur d'un visuel : le `title` s'il est propre, sinon un
/// libellé neutre « Visuel N » (jamais un nom de fichier).
String relaxationVisualLabel(RelaxationVideo v, int indexZeroBased) {
  final t = v.title.trim();
  if (t.isEmpty ||
      t.toLowerCase() == v.slug.toLowerCase() ||
      _technicalTitle.hasMatch(t)) {
    return 'Visuel ${indexZeroBased + 1}';
  }
  return t;
}

/// Ouvre la bottom sheet « Choisir le visuel ». Ne construit AUCUN
/// `VideoPlayerController` : uniquement du texte et, si `thumbnail_url` existe,
/// une image légère. Retourne `null` si l'utilisateur ferme sans choisir.
Future<RelaxationVisualChoice?> showRelaxationVisualPicker(
  BuildContext context, {
  required List<RelaxationVideo> videos,
  String? currentSlug,
}) {
  return showModalBottomSheet<RelaxationVisualChoice>(
    context: context,
    backgroundColor: AuryelColors.surface,
    isScrollControlled: true,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _VisualPickerSheet(videos: videos, currentSlug: currentSlug),
  );
}

class _VisualPickerSheet extends StatelessWidget {
  const _VisualPickerSheet({required this.videos, this.currentSlug});

  final List<RelaxationVideo> videos;
  final String? currentSlug;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.7;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AuryelColors.warmBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'Choisir le visuel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AuryelText.display(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.textCream,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'sans son',
                    style: AuryelText.body(
                      fontSize: 11,
                      color: AuryelColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                children: [
                  _RandomTile(
                    onTap: () => Navigator.of(
                      context,
                    ).pop(RelaxationVisualChoice.random()),
                  ),
                  for (var i = 0; i < videos.length; i++)
                    _VisualTile(
                      label: relaxationVisualLabel(videos[i], i),
                      video: videos[i],
                      selected: videos[i].slug == currentSlug,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(RelaxationVisualChoice.video(videos[i])),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RandomTile extends StatelessWidget {
  const _RandomTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: AuryelColors.goldGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.shuffle_rounded,
                  size: 22,
                  color: AuryelColors.backgroundDeep,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aléatoire',
                      style: AuryelText.body(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.textCream,
                      ),
                    ),
                    Text(
                      'Laisser Auryel choisir un visuel apaisant',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AuryelText.body(
                        fontSize: 11.5,
                        color: AuryelColors.textMuted,
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

class _VisualTile extends StatelessWidget {
  const _VisualTile({
    required this.label,
    required this.video,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final RelaxationVideo video;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ambiance = video.category.trim().toLowerCase();
    final showAmbiance =
        ambiance.isNotEmpty && ambiance != 'calm' && ambiance != 'generic';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              _Thumb(url: video.thumbnailUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AuryelText.body(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.textCream,
                      ),
                    ),
                    if (showAmbiance)
                      Text(
                        ambiance,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AuryelText.body(
                          fontSize: 11.5,
                          color: AuryelColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: AuryelColors.goldLight,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vignette légère : `thumbnail_url` si disponible (image réseau, échec ->
/// repli), sinon un placeholder propre — on n'invente JAMAIS d'image.
class _Thumb extends StatelessWidget {
  const _Thumb({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: AuryelColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AuryelColors.gold.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: const Icon(
        PhosphorIconsRegular.image,
        size: 18,
        color: AuryelColors.textMuted,
      ),
    );
    final u = url;
    if (u == null || u.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        u,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : placeholder,
      ),
    );
  }
}
