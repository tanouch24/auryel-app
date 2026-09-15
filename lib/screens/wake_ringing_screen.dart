import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../data/content_repository.dart';
import '../data/wake_message.dart';
import '../data/wake_message_catalog.dart';
import '../data/wake_message_selector.dart';
import '../services/wake_alarm_channel.dart';
import '../state/rewards_controller.dart';
import '../theme/auryel_theme.dart';
import 'wake_after_screen.dart';

/// Lit le message vocal du Réveil Auryel : MP3 pré-généré (R2) si
/// `audio_url` est fourni, sinon repli TextToSpeech LOCAL (voix native
/// Android) — jamais un appel TTS payant au moment où le réveil sonne,
/// jamais de dépendance réseau pour que le réveil parle.
abstract class WakeVoicePlayer {
  Future<void> speak(WakeMessage message);
  Future<void> stop();
}

class DefaultWakeVoicePlayer implements WakeVoicePlayer {
  DefaultWakeVoicePlayer({ap.AudioPlayer? player, FlutterTts? tts})
    : _player = player ?? ap.AudioPlayer(),
      _tts = tts ?? FlutterTts();

  final ap.AudioPlayer _player;
  final FlutterTts _tts;

  @override
  Future<void> speak(WakeMessage message) async {
    final url = message.audioUrl;
    if (url != null && url.isNotEmpty) {
      try {
        await _player.play(ap.UrlSource(url));
        return;
      } catch (_) {
        /* échec MP3 -> repli TTS ci-dessous, jamais un réveil muet */
      }
    }
    try {
      await _tts.setLanguage('fr-FR');
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(1.0);
      await _tts.speak(message.text);
    } catch (_) {
      /* aucune voix disponible -> l'écran reste utilisable (texte affiché,
         bouton Éteindre toujours actif) */
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

/// Écran d'alarme du Réveil Auryel — calme, jamais agressif. Affiché en
/// plein écran par-dessus le verrouillage (déclenché nativement, voir
/// `MainActivity`/`WakeAlarmReceiver`). Message choisi au hasard parmi les
/// messages actifs (anti-répétition ~20 derniers), fonctionne SANS réseau
/// (cache local -> repli embarqué).
class WakeRingingScreen extends StatefulWidget {
  const WakeRingingScreen({
    super.key,
    this.voicePlayer,
    this.alarmChannel,
    this.messageSelector,
    this.messagesOverride,
    this.now,
  });

  /// Test uniquement : lecteur vocal injecté (aucun canal plateforme réel).
  final WakeVoicePlayer? voicePlayer;
  final WakeAlarmChannel? alarmChannel;
  final WakeMessageSelector? messageSelector;

  /// Test uniquement : catalogue de messages injecté (sans [ContentScope]).
  final List<WakeMessage>? messagesOverride;
  final DateTime? now;

  @override
  State<WakeRingingScreen> createState() => _WakeRingingScreenState();
}

class _WakeRingingScreenState extends State<WakeRingingScreen> {
  late final WakeVoicePlayer _voice =
      widget.voicePlayer ?? DefaultWakeVoicePlayer();
  late final WakeAlarmChannel _channel =
      widget.alarmChannel ?? MethodChannelWakeAlarm();
  late final WakeMessageSelector _selector =
      widget.messageSelector ?? WakeMessageSelector();

  WakeMessage? _message;
  Timer? _clockTimer;
  Timer? _motivationTimer;
  DateTime _now = DateTime.now();
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _now = widget.now ?? DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _loadAndSpeak();
  }

  Future<void> _loadAndSpeak() async {
    final override = widget.messagesOverride;
    final catalog = override ?? await _resolveCatalog();
    if (!mounted) return;
    final picked = await _selector.pick(catalog);
    if (!mounted) return;
    setState(() => _message = picked);
    if (picked != null) {
      // La sonnerie native reste prioritaire. La motivation arrive après un
      // court délai, afin de ne jamais parler par-dessus le signal d'alarme.
      _motivationTimer = Timer(const Duration(seconds: 8), () {
        if (mounted && !_acting) unawaited(_voice.speak(picked));
      });
    }
  }

  Future<List<WakeMessage>> _resolveCatalog() async {
    final content = ContentScope.maybeOf(context);
    if (content == null) return WakeMessageCatalog.items;
    try {
      final list = await content.wakeMessages();
      return list.isEmpty ? WakeMessageCatalog.items : list;
    } catch (_) {
      return WakeMessageCatalog.items;
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _motivationTimer?.cancel();
    unawaited(_voice.stop());
    super.dispose();
  }

  String get _timeLabel =>
      '${_now.hour.toString().padLeft(2, '0')}:'
      '${_now.minute.toString().padLeft(2, '0')}';

  Future<void> _turnOff() async {
    if (_acting) return;
    setState(() => _acting = true);
    _motivationTimer?.cancel();
    await _voice.stop();
    await _channel.stopRinging();
    if (!mounted) return;
    // GROS CHANTIER AURYEL (Prompt 2/5) — ÉTOILES `wake_completed` : réclamée
    // UNIQUEMENT ici, sur l'extinction RÉELLE d'une alarme qui a RÉELLEMENT
    // sonné — jamais à l'ouverture de l'onglet Réveil, jamais à la simple
    // configuration d'une alarme (WakeSettingsScreen n'appelle jamais
    // `claim`), jamais sur `_snooze()` (répéter n'est pas terminer le
    // réveil). Fire-and-forget, jamais bloquant pour la transition vers
    // « Belle journée » : aucune erreur réseau ne doit retarder l'écran
    // suivant.
    unawaited(RewardsScope.maybeReadOf(context)?.claim('wake_completed'));
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const WakeAfterScreen()),
    );
  }

  Future<void> _snooze() async {
    if (_acting) return;
    setState(() => _acting = true);
    _motivationTimer?.cancel();
    await _voice.stop();
    await _channel.stopRinging();
    await _channel.snoozeAlarm(minutes: 10);
    if (!mounted) return;
    // `pop()` DIRECT — jamais `maybePop()` : l'écran est volontairement
    // couvert par `PopScope(canPop: false)` (retour système bloqué), ce qui
    // bloquerait aussi `maybePop()` (elle consulte `popDisposition`). `pop()`
    // reste le seul moyen PROGRAMMATIQUE de quitter cet écran nous-mêmes.
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              _wakeImageAsset,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
            Container(
              color: AuryelColors.backgroundDeep.withValues(alpha: 0.82),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 24,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      'AURYEL · RÉVEIL',
                      style: AuryelText.body(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.goldLight,
                        letterSpacing: 3,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _timeLabel,
                      style: AuryelText.display(
                        fontSize: 64,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.textCream,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      _message?.text ?? 'Prends un instant pour toi.',
                      textAlign: TextAlign.center,
                      style: AuryelText.body(
                        fontSize: 16,
                        height: 1.5,
                        color: AuryelColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Semantics(
                      button: true,
                      label: 'Éteindre le réveil',
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _acting ? null : _turnOff,
                          child: Ink(
                            width: 112,
                            height: 112,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AuryelColors.goldGradient,
                            ),
                            child: const Icon(
                              Icons.alarm_off_rounded,
                              size: 46,
                              color: AuryelColors.backgroundDeep,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Éteindre',
                      style: AuryelText.body(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.textCream,
                      ),
                    ),
                    const SizedBox(height: 22),
                    TextButton.icon(
                      onPressed: _acting ? null : _snooze,
                      icon: const PhosphorIcon(
                        PhosphorIconsRegular.clockClockwise,
                        size: 16,
                        color: AuryelColors.textMuted,
                      ),
                      label: Text(
                        'Répéter dans 10 min',
                        style: AuryelText.body(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AuryelColors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _wakeImageAsset {
    const images = [
      'assets/images/wake/reveil_aube_lac_brume_01.jpg',
      'assets/images/wake/reveil_foret_bouleaux_etang_03.jpg',
      'assets/images/wake/reveil_ocean_plage_aube_01.jpg',
    ];
    return images[(_now.day + _now.hour) % images.length];
  }
}
