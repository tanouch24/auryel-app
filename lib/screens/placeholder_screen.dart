import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../theme/auryel_theme.dart';

/// Placeholder stylé pour un onglet pas encore construit.
/// Reprend les tokens Auryel pour que la navigation ne casse jamais le ton.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle = 'Bientôt.',
  });

  final String title;
  final PhosphorIconData icon;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    // Scaffold propre (pas juste un Container) : cet écran est parfois un
    // enfant d'onglet dans le Scaffold de MainNavShell, mais aussi parfois
    // poussé seul via Navigator.push (ex: "Espace") — sans ancêtre Material
    // propre, Text retombe sur DefaultTextStyle.fallback() (souligné jaune debug).
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AuryelColors.surface,
                    border: Border.all(color: AuryelColors.warmBorder),
                  ),
                  child: Center(
                    child: PhosphorIcon(
                      icon,
                      size: 26,
                      color: AuryelColors.gold,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: AuryelText.display(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: AuryelText.body(
                      fontSize: 13,
                      color: AuryelColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
