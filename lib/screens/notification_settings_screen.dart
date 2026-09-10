import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../notifications/app_settings_opener.dart';
import '../notifications/notification_coordinator.dart';
import '../notifications/notification_service.dart';
import '../theme/auryel_theme.dart';
import '../widgets/gold_button.dart';

/// « Mon compte » -> Notifications. Écran volontairement minimal : un état, une
/// action contextuelle. AUCUN toggle par type (pensée / méditation / sommeil…)
/// tant qu'il n'y a pas de backend de préférences.
///
/// La demande d'autorisation n'est JAMAIS automatique : elle passe par le CTA
/// explicite « Activer les notifications ».
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({
    super.key,
    this.serviceOverride,
    this.settingsOpener = const SystemAppSettingsOpener(),
  });

  /// Test uniquement : sinon lu depuis [NotificationScope].
  final AuryelNotificationService? serviceOverride;
  final AppSettingsOpener settingsOpener;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  AuryelNotificationService? _service;
  NotificationPermissionStatus? _status;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _service ??=
        widget.serviceOverride ?? NotificationScope.maybeOf(context)?.service;
    if (_status == null) _load();
  }

  Future<void> _load() async {
    final s = _service;
    final status = s == null
        ? NotificationPermissionStatus.unavailable
        : await s.permissionStatus();
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _activate() async {
    final s = _service;
    if (s == null || _busy) return;
    setState(() => _busy = true);
    final status = await s.requestPermission();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = status;
    });
  }

  Future<void> _openSettings() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.settingsOpener.open();
    if (mounted) setState(() => _busy = false);
  }

  ({String text, String? ctaLabel, VoidCallback? onCta}) get _view {
    switch (_status) {
      case NotificationPermissionStatus.authorized:
      case NotificationPermissionStatus.provisional:
        return (
          text: 'Les notifications Auryel sont activées.',
          ctaLabel: null,
          onCta: null,
        );
      case NotificationPermissionStatus.notDetermined:
        return (
          text: 'Tu n’as pas encore activé les notifications Auryel.',
          ctaLabel: 'Activer les notifications',
          onCta: _busy ? null : _activate,
        );
      case NotificationPermissionStatus.denied:
        return (
          text:
              'Les notifications sont désactivées pour Auryel. Tu peux les '
              'réactiver depuis les réglages de ton téléphone.',
          ctaLabel: 'Ouvrir les réglages',
          onCta: _busy ? null : _openSettings,
        );
      case NotificationPermissionStatus.unavailable:
      case null:
        return (
          text:
              'Les notifications ne sont pas encore disponibles dans cette '
              'version d’Auryel.',
          ctaLabel: null,
          onCta: null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _view;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
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
                  'Notifications Auryel',
                  style: AuryelText.display(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.textCream,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  decoration: BoxDecoration(
                    color: AuryelColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AuryelColors.warmBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const PhosphorIcon(
                            PhosphorIconsRegular.bell,
                            size: 16,
                            color: AuryelColors.gold,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'ÉTAT',
                            style: AuryelText.body(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AuryelColors.textMuted,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        v.text,
                        style: AuryelText.body(
                          fontSize: 13,
                          height: 1.4,
                          color: AuryelColors.textSecondary,
                        ),
                      ),
                      if (v.ctaLabel != null) ...[
                        const SizedBox(height: 16),
                        AuryelGoldButton(
                          label: _busy ? 'Un instant…' : v.ctaLabel!,
                          enabled: v.onCta != null,
                          onTap: v.onCta ?? () {},
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Auryel n’envoie que des rappels doux (pensée du jour, ton '
                  'Moment) et, rarement, un message personnel de ton conseiller.',
                  style: AuryelText.body(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AuryelColors.textMuted,
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
