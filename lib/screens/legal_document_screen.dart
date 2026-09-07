import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../theme/auryel_theme.dart';

/// Écran de lecture d'un document juridique DANS l'application (lot J3).
///
/// Volontairement minimal : un titre, un corps scrollable, un bouton retour.
/// Aucun package, aucune WebView. Le corps est un texte brut : une ligne
/// entièrement en capitales devient un titre de section, une ligne vide une
/// respiration, le reste des paragraphes qui se recomposent à la largeur de
/// l'écran.
///
/// Cet écran ne déclenche AUCUNE action (pas d'achat, pas d'appel réseau) : il
/// se contente d'afficher le texte fourni.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  static bool _isHeading(String line) {
    if (line.isEmpty || line.length > 70) return false;
    if (line != line.toUpperCase()) return false;
    return RegExp(r'[A-ZÀ-Ýa-zà-ý]').hasMatch(line);
  }

  List<Widget> _blocks() {
    final widgets = <Widget>[];
    final buffer = <String>[];

    void flushParagraph() {
      if (buffer.isEmpty) return;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            buffer.join(' '),
            style: AuryelText.body(
              fontSize: 13,
              height: 1.55,
              color: AuryelColors.textSecondary,
            ),
          ),
        ),
      );
      buffer.clear();
    }

    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        flushParagraph();
        continue;
      }
      if (_isHeading(line)) {
        flushParagraph();
        widgets.add(
          Padding(
            padding: EdgeInsets.only(top: widgets.isEmpty ? 0 : 10, bottom: 8),
            child: Text(
              line,
              style: AuryelText.body(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AuryelColors.gold,
                letterSpacing: 1.2,
              ),
            ),
          ),
        );
        continue;
      }
      buffer.add(line);
    }
    flushParagraph();
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const PhosphorIcon(
                      PhosphorIconsRegular.arrowLeft,
                      size: 20,
                      color: AuryelColors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: AuryelText.display(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.textCream,
                  ),
                ),
                const SizedBox(height: 18),
                ..._blocks(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
