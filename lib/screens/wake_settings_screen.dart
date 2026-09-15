import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/wake_sound_catalog.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../data/wake_alarm_prefs.dart';
import '../services/wake_alarm_channel.dart';
import '../theme/auryel_theme.dart';
import '../widgets/main_nav_scope.dart';
import 'wake_ringing_screen.dart';

/// Onglet « Réveil » — Réveil Auryel vocal. Volontairement SIMPLE :
/// l'utilisateur choisit une heure, active/désactive, et éventuellement des
/// jours de semaine. Il ne choisit JAMAIS sa phrase, une catégorie ou une
/// voix (sélection automatique côté [WakeMessageSelector]).
class WakeSettingsScreen extends StatefulWidget {
  const WakeSettingsScreen({super.key, this.channel, this.prefsStore});

  /// Test uniquement : pont natif / stockage injectés.
  final WakeAlarmChannel? channel;
  final WakeAlarmPrefsStore? prefsStore;

  @override
  State<WakeSettingsScreen> createState() => _WakeSettingsScreenState();
}

/// Lundi..dimanche affichés dans cet ordre -> valeurs `Calendar.DAY_OF_WEEK`
/// natives correspondantes (2=lundi..7=samedi, 1=dimanche).
const List<({String label, int day})> _kWeekDays = [
  (label: 'L', day: 2),
  (label: 'M', day: 3),
  (label: 'M', day: 4),
  (label: 'J', day: 5),
  (label: 'V', day: 6),
  (label: 'S', day: 7),
  (label: 'D', day: 1),
];

class _WakeSettingsScreenState extends State<WakeSettingsScreen>
    with WidgetsBindingObserver {
  late final WakeAlarmChannel _channel =
      widget.channel ?? MethodChannelWakeAlarm();
  late final WakeAlarmPrefsStore _store =
      widget.prefsStore ?? WakeAlarmPrefsStore();

  WakeAlarmSettings _settings = WakeAlarmSettings.defaults;
  bool _loading = true;
  bool _awaitingPermission = false;
  int? _lastNavIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour depuis le réglage système « Alarmes et rappels » -> on
    // retente l'activation si l'utilisateur l'attendait.
    if (state == AppLifecycleState.resumed && _awaitingPermission) {
      _awaitingPermission = false;
      _tryEnable();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nav = MainNavScope.maybeOf(context);
    if (nav != null &&
        nav.currentIndex != _lastNavIndex &&
        nav.currentIndex != kTabReveil) {}
    _lastNavIndex = nav?.currentIndex;
  }

  Future<void> _load() async {
    final s = await _store.load();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _loading = false;
    });
  }

  Future<void> _persist(WakeAlarmSettings next) async {
    setState(() => _settings = next);
    await _store.save(next);
    await _channel.setAlarmSound(wakeSoundById(next.soundId).nativeResource);
    if (next.enabled) {
      await _channel.saveAlarm(
        enabled: true,
        hour: next.hour,
        minute: next.minute,
        days: next.days.toList(),
      );
    } else {
      await _channel.cancelAlarm();
    }
  }

  Future<void> _testWake() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            WakeRingingScreen(testMode: true, testSoundId: _settings.soundId),
      ),
    );
  }

  Future<void> _tryEnable() async {
    if (Platform.isAndroid) {
      final notification = await Permission.notification.request();
      if (!notification.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Les notifications sont nécessaires pour faire sonner le réveil.',
              ),
            ),
          );
        }
        return;
      }
    }
    final can = await _channel.canScheduleExactAlarms();
    if (!mounted) return;
    if (!can) {
      _awaitingPermission = true;
      await _showPermissionDialog();
      return;
    }
    final fullScreen = await _channel.canUseFullScreenIntent();
    if (!fullScreen) {
      _awaitingPermission = true;
      await _showFullScreenDialog();
      return;
    }
    await _persist(_settings.copyWith(enabled: true));
  }

  Future<void> _showFullScreenDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AuryelColors.surface,
        title: Text(
          'Affichage sur écran verrouillé',
          style: AuryelText.display(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Pour afficher le réveil au-dessus de l’écran verrouillé, autorise les notifications plein écran dans les réglages.',
          style: AuryelText.body(
            fontSize: 13.5,
            color: AuryelColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Plus tard'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _channel.requestFullScreenIntentPermission();
            },
            child: Text(
              'Ouvrir les réglages',
              style: AuryelText.body(
                color: AuryelColors.goldLight,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPermissionDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AuryelColors.surface,
        title: Text(
          'Autorisation nécessaire',
          style: AuryelText.display(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Text(
          "Pour sonner à l'heure exacte, Auryel a besoin de l'autorisation "
          "système « Alarmes et rappels ». Active-la dans les réglages, "
          'puis reviens ici.',
          style: AuryelText.body(
            fontSize: 13.5,
            color: AuryelColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Plus tard',
              style: AuryelText.body(color: AuryelColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _channel.requestExactAlarmPermission();
            },
            child: Text(
              'Ouvrir les réglages',
              style: AuryelText.body(
                color: AuryelColors.goldLight,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _settings.hour, minute: _settings.minute),
    );
    if (picked == null) return;
    await _persist(
      _settings.copyWith(hour: picked.hour, minute: picked.minute),
    );
  }

  void _toggleDay(int day) {
    final days = {..._settings.days};
    if (days.contains(day)) {
      days.remove(day);
    } else {
      days.add(day);
    }
    _persist(_settings.copyWith(days: days));
  }

  String get _timeLabel =>
      '${_settings.hour.toString().padLeft(2, '0')}:'
      '${_settings.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AuryelColors.gold),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: AuryelColors.backgroundGradient,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'AURYEL · RÉVEIL',
                style: AuryelText.body(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.gold,
                  letterSpacing: 3.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Commence ta journée avec Auryel',
                style: AuryelText.display(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.textCream,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Choisis l'heure de ton réveil et commence ta journée avec "
                'une voix douce et un message positif.',
                style: AuryelText.body(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AuryelColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AuryelColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AuryelColors.warmBorder),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Réveil',
                            style: AuryelText.body(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AuryelColors.textCream,
                            ),
                          ),
                        ),
                        Switch(
                          key: const Key('wake-enabled-switch'),
                          value: _settings.enabled,
                          activeThumbColor: AuryelColors.goldLight,
                          onChanged: (v) {
                            if (v) {
                              _tryEnable();
                            } else {
                              _persist(_settings.copyWith(enabled: false));
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _pickTime,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            const PhosphorIcon(
                              PhosphorIconsRegular.clock,
                              size: 20,
                              color: AuryelColors.goldLight,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _timeLabel,
                              style: AuryelText.display(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                color: AuryelColors.textCream,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              "Changer l'heure",
                              style: AuryelText.body(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AuryelColors.goldLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'JOURS (optionnel — tous les jours si aucun choisi)',
                        style: AuryelText.body(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AuryelColors.textMuted,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final d in _kWeekDays)
                          _DayChip(
                            label: d.label,
                            selected: _settings.days.contains(d.day),
                            onTap: () => _toggleDay(d.day),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _testWake,
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Tester mon réveil'),
              ),
              const SizedBox(height: 16),
              Text(
                'En cas de report, le réveil sonne à nouveau 10 minutes plus '
                'tard.',
                style: AuryelText.body(
                  fontSize: 11.5,
                  color: AuryelColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? AuryelColors.gold.withValues(alpha: 0.22)
              : Colors.transparent,
          border: Border.all(
            color: selected ? AuryelColors.goldLight : AuryelColors.warmBorder,
          ),
        ),
        child: Text(
          label,
          style: AuryelText.body(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? AuryelColors.goldLight : AuryelColors.textMuted,
          ),
        ),
      ),
    );
  }
}
