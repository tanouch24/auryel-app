import 'package:flutter/material.dart';

import '../theme/auryel_theme.dart';
import 'tarot_card_back.dart';

/// UX-B §9-§12 — les 22 arcanes présentés ENSEMBLE en éventail, comme un jeu
/// tenu en main. Flutter pur : `LayoutBuilder` + `Stack` + `Positioned` +
/// `Transform.rotate`. Aucune dépendance externe, **aucun scroll horizontal**,
/// aucun overflow entre ~320 dp et ~430 dp de large.
///
/// Hit testing (§12) : une couche de tuiles tapables PAVE la largeur — chaque
/// carte a sa propre zone, centre toujours exposé, aucune carte « cachée sous
/// les suivantes ». Les indices 0 et 21 sont aussi sélectionnables que le
/// milieu. Chaque tuile porte `ValueKey('tarot-back-<index>')`.
class TarotFan extends StatelessWidget {
  const TarotFan({
    super.key,
    required this.count,
    required this.selectionNumberFor,
    required this.onTap,
    this.enabled = true,
  });

  /// Nombre de cartes (22).
  final int count;

  /// Rang de sélection (1..3) de la carte d'index donné, ou `null`.
  final int? Function(int index) selectionNumberFor;

  /// Tap direct sur la carte d'index donné.
  final void Function(int index) onTap;

  /// `false` => les taps sont ignorés (phase révélée / sauvegarde en cours /
  /// 3 cartes déjà choisies).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 320.0;
        final n = count;

        // Carte dimensionnée par la largeur ET la hauteur disponibles.
        final cardW = (width / 5.6).clamp(44.0, 72.0);
        final maxCardH = (height - 56).clamp(80.0, 260.0);
        final cardH = (cardW * 1.5).clamp(80.0, maxCardH);

        // B8.1 §5 — marge de sécurité latérale : les cartes de bord sont
        // inclinées (Transform.rotate autour de bottomCenter) et légèrement
        // agrandies (scale 1.08) quand sélectionnées ; sans cet `edge` leur
        // coin supérieur dépasse hors du SizedBox sur écran étroit
        // (constat Galaxy A07). La bande de cartes est donc rétrécie de `edge`
        // de chaque côté -> plus aucun débordement horizontal.
        final edge = (cardW * 0.18).clamp(0.0, 16.0);

        // Pas horizontal : 1re carte à left=edge, dernière à left=width-cardW-edge.
        // => la bande occupe AU PLUS `width`, jamais plus.
        final span = (width - cardW - 2 * edge).clamp(0.0, double.infinity);
        final step = n > 1 ? span / (n - 1) : 0.0;

        // Arc en parabole (centre le plus haut) + légère inclinaison.
        final arc = (height * 0.16).clamp(16.0, 52.0);
        final maxTilt = (width / 900).clamp(0.26, 0.42);
        final baseTop = arc + 10.0;

        double axis(int i) => n > 1 ? (i / (n - 1)) * 2 - 1 : 0.0; // -1..1
        double liftFor(int i) => -arc * (1 - axis(i) * axis(i));
        double tiltFor(int i) => axis(i) * maxTilt;

        // Tuile tapable : légèrement plus large que le pas pour le confort du
        // doigt, mais CENTRÉE sur le centre réel de la carte -> mapping
        // déterministe (le centre d'une tuile n'est jamais recouvert).
        final pad = (step * 0.35).clamp(0.0, 8.0);
        final hitHeight = baseTop + cardH + 10.0;

        final decorative = <Widget>[];
        // Non sélectionnées d'abord (dessous), sélectionnées ensuite (au-dessus
        // de leurs voisines) — ordre de peinture du Stack.
        final paintOrder = <int>[
          for (var i = 0; i < n; i++)
            if (selectionNumberFor(i) == null) i,
          for (var i = 0; i < n; i++)
            if (selectionNumberFor(i) != null) i,
        ];
        for (final i in paintOrder) {
          final sel = selectionNumberFor(i);
          final lift = liftFor(i) + (sel != null ? -24.0 : 0.0);
          decorative.add(
            Positioned(
              left: edge + i * step,
              top: baseTop + lift,
              width: cardW,
              height: cardH,
              child: Transform.rotate(
                angle: tiltFor(i),
                alignment: Alignment.bottomCenter,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  scale: sel != null ? 1.08 : 1.0,
                  child: _FanCardBack(selectionNumber: sel),
                ),
              ),
            ),
          );
        }

        final hits = <Widget>[];
        for (var i = 0; i < n; i++) {
          final isLast = i == n - 1;
          final rawLeft = edge + i * step - pad;
          final left = rawLeft < 0 ? 0.0 : rawLeft;
          final rawW = isLast ? (cardW + 2 * pad) : (step + 2 * pad);
          // Ne jamais dépasser le bord droit du SizedBox.
          final w = (left + rawW > width ? width - left : rawW);
          hits.add(
            Positioned(
              left: left,
              top: 0,
              width: w <= 0 ? cardW : w,
              height: hitHeight,
              child: GestureDetector(
                key: ValueKey('tarot-back-$i'),
                behavior: HitTestBehavior.opaque,
                // Toujours un recognizer (la tuile reste hit-testable même
                // « désactivée ») ; le filtrage se fait ici.
                onTap: () {
                  if (enabled) onTap(i);
                },
                child: const SizedBox.expand(),
              ),
            ),
          );
        }

        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [...decorative, ...hits],
          ),
        );
      },
    );
  }
}

/// Dos de carte de l'éventail — délègue au dos partagé [TarotCardBack] (bleu
/// nuit + rosace or, cohérent avec le tapis). Carte choisie : bordure vive +
/// pastille numérotée.
class _FanCardBack extends StatelessWidget {
  const _FanCardBack({this.selectionNumber});

  final int? selectionNumber;

  @override
  Widget build(BuildContext context) {
    final selected = selectionNumber != null;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        TarotCardBack(selected: selected),
        if (selected)
          Positioned(
            top: -11,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AuryelColors.goldGradient,
              ),
              child: Text(
                '$selectionNumber',
                style: AuryelText.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AuryelColors.backgroundDeep,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
