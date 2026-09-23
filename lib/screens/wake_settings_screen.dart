import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/wake_sound_catalog.dart';
import '../data/wake_video.dart';
import '../data/content_repository.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../data/wake_alarm_prefs.dart';
import '../services/wake_alarm_channel.dart';
import '../theme/auryel_theme.dart';
import '../widgets/main_nav_scope.dart';
import '../widgets/wake_video_stage.dart';
import 'wake_ringing_screen.dart';

/// Onglet « Réveil » — Réveil Auryel. Volontairement SIMPLE :
/// l'utilisateur choisit une heure, active/désactive, et éventuellement des
/// jours de semaine. La vidéo complète du réveil est préparée en cache local
/// pour que l'alarme ne dépende pas d'un téléchargement au déclenchement.
class WakeSettingsScreen extends StatefulWidget {
  const WakeSettingsScreen({
    super.key,
    this.channel,
    this.prefsStore,
    this.onConfigured,
    this.onSkip,
    this.returnToOnboarding = false,
  });

  /// Test uniquement : pont natif / stockage injectés.
  final WakeAlarmChannel? channel;
  final WakeAlarmPrefsStore? prefsStore;
  final VoidCallback? onConfigured;
  final VoidCallback? onSkip;
  final bool returnToOnboarding;

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
  late final WakeVideoCache _videoCache = WakeVideoCache();

  WakeAlarmSettings _settings = WakeAlarmSettings.defaults;
  bool _loading = true;
  bool _awaitingPermission = false;
  int? _lastNavIndex;
  WakeVideo _dailyVideo = WakeVideoCatalog.pilot;
  bool _dailyVideoLoaded = false;
  final _previewStageKey = GlobalKey<WakeVideoStageState>();
  String? _previewPath;
  bool _previewFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoCache.close();
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
    if (!_dailyVideoLoaded) unawaited(_resolveDailyVideo(DateTime.now()));
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

  Future<WakeVideo> _resolveDailyVideo(DateTime date) async {
    final repository = ContentScope.maybeOf(context);
    final video = repository == null
        ? WakeVideoDailySelection.pick(WakeVideoCatalog.active, date)
        : await repository.wakeOfDay(date);
    if (mounted) {
      setState(() {
        _dailyVideo = video;
        _dailyVideoLoaded = true;
      });
      unawaited(_prepareWakeVideo(video));
    }
    return video;
  }

  Future<void> _prepareWakeVideo(WakeVideo video) async {
    final file = await _videoCache.prepare(video);
    if (!mounted) return;
    setState(() {
      _previewPath = file?.path;
      _previewFailed = file == null;
    });
  }

  Future<void> _persist(WakeAlarmSettings next) async {
    final target = WakeScheduleDate.nextTarget(
      DateTime.now(),
      next.hour,
      next.minute,
      next.days,
    );
    final repository = ContentScope.maybeOf(context);
    final catalog = repository == null
        ? WakeVideoCatalog.active
        : await repository.wakeVideos();
    final resolvedCatalog = catalog.isEmpty ? WakeVideoCatalog.active : catalog;
    final video = WakeVideoDailySelection.pick(resolvedCatalog, target);
    final schedule = <Map<String, dynamic>>[];
    var cursor = target;
    for (var i = 0; i < 31; i++) {
      final scheduledVideo = WakeVideoDailySelection.pick(
        resolvedCatalog,
        cursor,
      );
      schedule.add({
        'id': scheduledVideo.id,
        'url': scheduledVideo.remoteUrl,
        'title': scheduledVideo.title,
        'date': ContentRepository.dayString(cursor),
      });
      cursor = WakeScheduleDate.nextTarget(
        cursor.add(const Duration(minutes: 1)),
        next.hour,
        next.minute,
        next.days,
      );
    }
    unawaited(_videoCache.prepare(video));
    final snapshot = next.copyWith(
      wakeVideoId: video.id,
      wakeVideoUrl: video.remoteUrl,
      wakeVideoTitle: video.title,
      wakeTargetDate: ContentRepository.dayString(target),
    );
    setState(() => _settings = snapshot);
    await _store.save(snapshot);
    await _channel.setAlarmSound(
      wakeSoundById(snapshot.soundId).nativeResource,
    );
    if (next.enabled) {
      final scheduled = await _channel.saveAlarm(
        enabled: true,
        hour: snapshot.hour,
        minute: snapshot.minute,
        days: snapshot.days.toList(),
        wakeVideoId: snapshot.wakeVideoId,
        wakeVideoUrl: snapshot.wakeVideoUrl,
        wakeVideoTitle: snapshot.wakeVideoTitle,
        wakeTargetDate: snapshot.wakeTargetDate,
        wakeScheduleJson: jsonEncode(schedule),
      );
      if (scheduled) widget.onConfigured?.call();
    } else {
      await _channel.cancelAlarm();
    }
  }

  Future<void> _testWake() async {
    if (!mounted) return;
    final video = await _resolveDailyVideo(DateTime.now());
    await _videoCache.prepare(video);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WakeRingingScreen(
          testMode: true,
          video: video,
          cache: _videoCache,
          origin: widget.returnToOnboarding
              ? WakeRingingOrigin.onboardingPreview
              : WakeRingingOrigin.settingsPreview,
        ),
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
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 112),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'AURYEL · RÉVEIL',
                      style: AuryelText.overline(color: AuryelColors.gold),
                    ),
                  ),
                  if (widget.onSkip != null)
                    TextButton(
                      onPressed: widget.onSkip,
                      style: TextButton.styleFrom(
                        foregroundColor: AuryelColors.textMuted,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      child: const Text('Plus tard'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Commence ta journée avec Auryel',
                style: AuryelText.screenTitle(),
              ),
              const SizedBox(height: 8),
              Text(
                "Choisis l'heure de ton réveil, puis laisse Auryel t'offrir "
                'un moment pour toi avant que la journée commence.',
                style: AuryelText.bodySecondary(
                  color: AuryelColors.textSecondary,
                ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AuryelColors.surfaceLight, AuryelColors.surface],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: AuryelColors.gold.withValues(alpha: 0.32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AuryelColors.backgroundDeep.withValues(alpha: 0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aperçu du réveil du jour',
                      style: AuryelText.overline(color: AuryelColors.gold),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      key: const Key('wake-settings-preview'),
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        height: 184,
                        width: double.infinity,
                        child: _previewPath == null
                            ? Container(
                                color: AuryelColors.backgroundDeep,
                                alignment: Alignment.center,
                                child: Icon(
                                  _previewFailed
                                      ? Icons.wb_sunny_outlined
                                      : Icons.alarm_rounded,
                                  size: 48,
                                  color: AuryelColors.goldLight,
                                ),
                              )
                            : WakeVideoStage(
                                key: _previewStageKey,
                                file: File(_previewPath!),
                                muted: true,
                              ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _settings.enabled
                                    ? 'Réveil activé'
                                    : 'Réveil en pause',
                                style: AuryelText.cardTitle(),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _settings.enabled
                                    ? 'Auryel sera là demain matin'
                                    : 'Prends le temps de le configurer',
                                style: AuryelText.bodySecondary(),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _settings.enabled
                                ? AuryelColors.gold.withValues(alpha: 0.18)
                                : AuryelColors.backgroundDeep.withValues(
                                    alpha: 0.45,
                                  ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Switch(
                            key: const Key('wake-enabled-switch'),
                            value: _settings.enabled,
                            activeThumbColor: AuryelColors.goldLight,
                            activeTrackColor: AuryelColors.goldDark,
                            inactiveThumbColor: AuryelColors.textMuted,
                            inactiveTrackColor: AuryelColors.backgroundDeep,
                            onChanged: (v) {
                              if (v) {
                                _tryEnable();
                              } else {
                                _persist(_settings.copyWith(enabled: false));
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    InkWell(
                      onTap: _pickTime,
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                        decoration: BoxDecoration(
                          color: AuryelColors.backgroundDeep.withValues(
                            alpha: 0.35,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AuryelColors.warmBorder),
                        ),
                        child: Row(
                          children: [
                            const PhosphorIcon(
                              PhosphorIconsRegular.clock,
                              size: 20,
                              color: AuryelColors.goldLight,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Prochain réveil',
                                    style: AuryelText.overline(),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _timeLabel,
                                    style: AuryelText.display(
                                      fontSize: 36,
                                      fontWeight: FontWeight.w700,
                                      color: AuryelColors.textCream,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AuryelColors.goldLight,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                decoration: BoxDecoration(
                  color: AuryelColors.surface.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AuryelColors.warmBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AuryelColors.gold.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.wb_sunny_rounded,
                            color: AuryelColors.goldLight,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Réveil du jour',
                                style: AuryelText.cardTitle(),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Une nouvelle attention chaque matin',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AuryelText.bodySecondary(
                                  color: AuryelColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_dailyVideo.durationSeconds != null)
                          Text(
                            '${_dailyVideo.durationSeconds}s',
                            style: AuryelText.overline(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _testWake,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Tester mon réveil'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AuryelColors.gold,
                          foregroundColor: AuryelColors.backgroundDeep,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(2, 18, 2, 4),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AuryelColors.warmBorder),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Répétition',
                      style: AuryelText.body(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.textCream,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _settings.days.isEmpty
                          ? 'Aucun jour choisi · tous les jours'
                          : 'Jours sélectionnés',
                      style: AuryelText.bodySecondary(),
                    ),
                    const SizedBox(height: 14),
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
                    const SizedBox(height: 14),
                    Text(
                      'En cas de report, le réveil sonne à nouveau 10 minutes plus tard.',
                      style: AuryelText.bodySecondary(),
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
