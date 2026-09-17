import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/wake_alarm_prefs.dart';
import '../../data/wake_video.dart';
import '../../ads/ad_service.dart';
import '../../theme/auryel_theme.dart';
import '../../widgets/wake_video_stage.dart';
import '../wake_settings_screen.dart';
import 'notification_onboarding_screen.dart';

/// Découverte ponctuelle du Réveil V2 pendant l'expérience d'accueil.
///
/// Cette étape ne possède aucun état métier propre : elle ne fait que montrer
/// le média du Réveil puis délègue la configuration à [WakeSettingsScreen].
class WakeOnboardingScreen extends StatefulWidget {
  const WakeOnboardingScreen({super.key, this.cache, this.onFinished});

  final WakeVideoCache? cache;
  final VoidCallback? onFinished;

  @override
  State<WakeOnboardingScreen> createState() => _WakeOnboardingScreenState();
}

class _WakeOnboardingScreenState extends State<WakeOnboardingScreen> {
  late final WakeVideoCache _cache = widget.cache ?? WakeVideoCache();
  final _stageKey = GlobalKey<WakeVideoStageState>();
  String? _videoPath;
  bool _videoFailed = false;
  bool _configured = false;
  WakeAlarmSettings? _savedSettings;

  @override
  void initState() {
    super.initState();
    AuryelAds.instance.setOnboardingFlowActive(true);
    unawaited(_loadPreview());
  }

  Future<void> _loadPreview() async {
    final file = await _cache.prepare(WakeVideoCatalog.pilot);
    if (!mounted) return;
    setState(() {
      _videoPath = file?.path;
      _videoFailed = file == null;
    });
  }

  @override
  void dispose() {
    AuryelAds.instance.setOnboardingFlowActive(false);
    unawaited(_stageKey.currentState?.stop());
    if (widget.cache == null) _cache.close();
    super.dispose();
  }

  void _finish() {
    if (!mounted) return;
    if (widget.onFinished != null) {
      widget.onFinished!.call();
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const NotificationOnboardingScreen()),
      (route) => false,
    );
  }

  Future<void> _configure() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WakeSettingsScreen(
          onConfigured: () => Navigator.of(context).pop(true),
          onSkip: () => Navigator.of(context).pop(false),
        ),
      ),
    );
    if (!mounted) return;
    final settings = await WakeAlarmPrefsStore().load();
    if (settings.enabled) {
      setState(() {
        _configured = true;
        _savedSettings = settings;
      });
    }
  }

  String _time(WakeAlarmSettings settings) =>
      '${settings.hour.toString().padLeft(2, '0')}:${settings.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (_configured && _savedSettings != null) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AuryelColors.backgroundGradient),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.alarm_rounded, size: 48, color: AuryelColors.goldLight),
                    const SizedBox(height: 20),
                    Text('Votre réveil est prêt', style: AuryelText.display(fontSize: 25), textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    Text('Il sonnera à ${_time(_savedSettings!)}.', style: AuryelText.body(color: AuryelColors.textSecondary)),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      key: const Key('wake-onboarding-continue'),
                      onPressed: _finish,
                      child: const Text('Continuer'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final path = _videoPath;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AuryelColors.backgroundGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('RÉVEIL AURYEL', style: AuryelText.body(color: AuryelColors.gold, letterSpacing: 3.2)),
                const SizedBox(height: 14),
                Text('Réveillez-vous avec Auryel', style: AuryelText.display(fontSize: 27)),
                const SizedBox(height: 10),
                Text('Commencez votre journée avec une expérience pensée pour vous réveiller en douceur.', style: AuryelText.body(color: AuryelColors.textSecondary, height: 1.45)),
                const SizedBox(height: 22),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    height: 250,
                    child: path == null
                        ? Container(
                            color: AuryelColors.surface,
                            alignment: Alignment.center,
                            child: Icon(_videoFailed ? Icons.wb_sunny_outlined : Icons.alarm_rounded, size: 58, color: AuryelColors.goldLight),
                          )
                        : WakeVideoStage(key: _stageKey, file: File(path), muted: false),
                  ),
                ),
                const SizedBox(height: 22),
                ElevatedButton(
                  key: const Key('wake-onboarding-configure'),
                  onPressed: _configure,
                  child: const Text('Configurer mon réveil'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('wake-onboarding-later'),
                  onPressed: _finish,
                  child: const Text('Plus tard'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
