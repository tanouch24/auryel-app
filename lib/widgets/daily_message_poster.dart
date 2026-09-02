import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/daily_message.dart';
import '../theme/auryel_theme.dart';

/// B8.3 §3-C — 3 compositions locales de l'affiche partageable. Même contenu
/// (phrase du jour + date + AURYEL), hiérarchie / mise en page différentes.
/// Toutes dans la DA Auryel (dégradé de fond, or, Inter). Aucune génération
/// externe, aucun appel réseau.
enum PosterVariant { classic, editorial, minimal }

/// Affiche partageable du message du jour — carte verticale (ratio 9:16, cible
/// 1080×1920). Le rendu à l'écran est libre (le parent donne la largeur, la
/// hauteur suit le ratio) ; l'export PNG passe par [capturePng] (1080 px large).
class DailyMessagePoster extends StatelessWidget {
  const DailyMessagePoster({
    super.key,
    required this.message,
    this.boundaryKey,
    this.variant = PosterVariant.classic,
  });

  final DailyMessage message;
  final PosterVariant variant;

  /// Clé du [RepaintBoundary] à capturer (fournie par la feuille de détail).
  final GlobalKey? boundaryKey;

  /// Ratio de l'affiche — 1080 × 1920.
  static const double aspectRatio = 1080 / 1920;

  static const double _designWidth = 1080;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: boundaryKey,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: _designWidth,
            height: _designWidth / aspectRatio,
            child: _PosterBody(message: message, variant: variant),
          ),
        ),
      ),
    );
  }

  /// Capture le [RepaintBoundary] identifié par [key] en PNG 1080 px de large.
  /// Renvoie `null` si le boundary n'est pas monté / peint, ou si la
  /// rasterisation n'aboutit pas (garde-fou : la capture ne doit JAMAIS bloquer
  /// le partage — on retombe alors sur un partage texte seul).
  static Future<Uint8List?> capturePng(GlobalKey key) async {
    try {
      final ctx = key.currentContext;
      final obj = ctx?.findRenderObject();
      if (obj is! RenderRepaintBoundary) return null;
      final logicalWidth = obj.size.width;
      if (logicalWidth <= 0) return null;
      final pixelRatio = (_designWidth / logicalWidth).clamp(1.0, 6.0);
      final ui.Image image = await obj
          .toImage(pixelRatio: pixelRatio)
          .timeout(const Duration(seconds: 2));
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        return bytes?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------

class _PosterBody extends StatelessWidget {
  const _PosterBody({required this.message, required this.variant});

  final DailyMessage message;
  final PosterVariant variant;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: AuryelColors.backgroundGradient,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _Halo(),
          switch (variant) {
            PosterVariant.classic => _ClassicLayout(message: message),
            PosterVariant.editorial => _EditorialLayout(message: message),
            PosterVariant.minimal => _MinimalLayout(message: message),
          },
        ],
      ),
    );
  }
}

class _Halo extends StatelessWidget {
  const _Halo();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 420,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          width: 780,
          height: 780,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AuryelColors.gold.withValues(alpha: 0.15),
                AuryelColors.gold.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _rule(double width, {double alpha = 0.5}) => Container(
      width: width,
      height: 2,
      color: AuryelColors.gold.withValues(alpha: alpha),
    );

Widget _diamond({double size = 20}) => Transform.rotate(
      angle: 0.785398,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: AuryelColors.goldGradient,
          borderRadius: BorderRadius.circular(size * 0.2),
        ),
      ),
    );

Widget _wordmark({double fontSize = 68, double letterSpacing = 16}) => ShaderMask(
      shaderCallback: (b) => AuryelColors.goldGradient.createShader(b),
      child: Text(
        'AURYEL',
        style: AuryelText.display(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: letterSpacing,
        ),
      ),
    );

Widget _messageText({
  required DailyMessage m,
  required double fontSize,
  TextAlign align = TextAlign.center,
}) =>
    RichText(
      textAlign: align,
      text: TextSpan(
        style: AuryelText.display(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          height: 1.34,
        ),
        children: [
          TextSpan(text: m.leadText),
          TextSpan(
            text: m.accentText,
            style: AuryelText.display(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              color: AuryelColors.goldLight,
              height: 1.34,
            ),
          ),
        ],
      ),
    );

// --- Variante 1 : CLASSIQUE (wordmark en tête, message centré) --------------
class _ClassicLayout extends StatelessWidget {
  const _ClassicLayout({required this.message});

  final DailyMessage message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(96, 150, 96, 120),
      child: Column(
        children: [
          _rule(380),
          const SizedBox(height: 36),
          _wordmark(),
          const SizedBox(height: 20),
          Text(
            message.dateLabel,
            style: AuryelText.body(
              fontSize: 26,
              fontWeight: FontWeight.w500,
              color: AuryelColors.textMuted,
              letterSpacing: 6,
            ),
          ),
          const Spacer(),
          _diamond(),
          const SizedBox(height: 56),
          _messageText(m: message, fontSize: 78),
          const SizedBox(height: 56),
          _diamond(),
          const Spacer(),
          Text(
            'Ton message du jour',
            style: AuryelText.body(
              fontSize: 30,
              fontWeight: FontWeight.w500,
              color: AuryelColors.textSecondary,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 40),
          _rule(380),
        ],
      ),
    );
  }
}

// --- Variante 2 : ÉDITORIALE (cadre fin, message haut-gauche) ---------------
class _EditorialLayout extends StatelessWidget {
  const _EditorialLayout({required this.message});

  final DailyMessage message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(52),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: AuryelColors.gold.withValues(alpha: 0.55),
            width: 2,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(72, 90, 72, 90),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _wordmark(fontSize: 46, letterSpacing: 12),
            const SizedBox(height: 14),
            Text(
              message.dateLabel,
              style: AuryelText.body(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                color: AuryelColors.textMuted,
                letterSpacing: 5,
              ),
            ),
            const Spacer(flex: 2),
            _diamond(size: 24),
            const SizedBox(height: 44),
            _messageText(m: message, fontSize: 84, align: TextAlign.left),
            const Spacer(flex: 3),
            _rule(220),
            const SizedBox(height: 22),
            Text(
              'TON MESSAGE DU JOUR',
              style: AuryelText.body(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AuryelColors.textMuted,
                letterSpacing: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Variante 3 : MINIMALE (message plein centre, signature discrète) -------
class _MinimalLayout extends StatelessWidget {
  const _MinimalLayout({required this.message});

  final DailyMessage message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(110, 180, 110, 150),
      child: Column(
        children: [
          const Spacer(flex: 3),
          _diamond(size: 16),
          const SizedBox(height: 64),
          _messageText(m: message, fontSize: 92),
          const SizedBox(height: 64),
          _diamond(size: 16),
          const Spacer(flex: 3),
          _rule(160, alpha: 0.4),
          const SizedBox(height: 26),
          Text(
            'AURYEL · ${message.dateLabel}',
            textAlign: TextAlign.center,
            style: AuryelText.body(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: AuryelColors.textMuted,
              letterSpacing: 5,
            ),
          ),
        ],
      ),
    );
  }
}
