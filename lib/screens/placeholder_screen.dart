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
  });

  final String title;
  final PhosphorIconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AuryelColors.backgroundGradient),
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
                  child: PhosphorIcon(icon, size: 26, color: AuryelColors.gold),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: AuryelText.display(fontSize: 22, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(
                'Bientôt.',
                style: AuryelText.body(fontSize: 13, color: AuryelColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
