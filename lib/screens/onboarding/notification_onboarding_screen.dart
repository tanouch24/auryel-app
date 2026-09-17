import 'package:flutter/material.dart';

import '../../notifications/notification_coordinator.dart';
import '../../notifications/notification_service.dart';
import '../../theme/auryel_theme.dart';
import '../../widgets/gold_button.dart';
import '../auryel_experience_screen.dart';

/// Étape 5/6 : demande explicite de permission Push. Un refus ne bloque
/// jamais la découverte ni l'entrée dans l'application.
class NotificationOnboardingScreen extends StatefulWidget {
  const NotificationOnboardingScreen({super.key, this.serviceOverride});

  final AuryelNotificationService? serviceOverride;

  @override
  State<NotificationOnboardingScreen> createState() =>
      _NotificationOnboardingScreenState();
}

class _NotificationOnboardingScreenState
    extends State<NotificationOnboardingScreen> {
  bool _busy = false;

  AuryelNotificationService? get _service =>
      widget.serviceOverride ?? NotificationScope.maybeOf(context)?.service;

  Future<void> _activate() async {
    final service = _service;
    if (_busy) return;
    setState(() => _busy = true);
    if (service != null) {
      await service.requestPermission();
    }
    if (!mounted) return;
    _continue();
  }

  void _continue() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuryelExperienceScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(gradient: AuryelColors.backgroundGradient),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(Icons.notifications_none_rounded,
                  size: 58, color: AuryelColors.goldLight),
              const SizedBox(height: 24),
              Text('Reste connecté à Auryel',
                  textAlign: TextAlign.center,
                  style: AuryelText.display(fontSize: 28,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              Text(
                'Reçois ta pensée du jour, les nouveautés de ton conseiller '
                'et tes moments Bien-être.',
                textAlign: TextAlign.center,
                style: AuryelText.body(color: AuryelColors.textSecondary,
                    height: 1.45),
              ),
              const Spacer(),
              AuryelGoldButton(
                label: _busy ? 'Activation…' : 'Activer les notifications',
                enabled: !_busy,
                onTap: _activate,
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _busy ? null : _continue,
                child: const Text('Plus tard'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
