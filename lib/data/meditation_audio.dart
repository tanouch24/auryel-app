import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// Fine abstraction du lecteur pour « Ton Moment ». Un SEUL exemplaire vit dans
/// `MeditationScreen`. Isolée pour être remplaçable en test (aucun canal
/// plateforme, aucun timer réel).
///
/// Contrat volontairement simple : [play] démarre une source, [pause]/[resume]
/// suspendent/reprennent, [stop] revient à zéro. La progression est poussée par
/// [onPosition] / [onDuration], et [onComplete] émet UNE fois à la fin
/// naturelle. Si le fichier est absent ou la plateforme indisponible, [play]
/// renvoie `false` et rien d'autre ne se produit (aucune exception remontée).
abstract class MeditationAudio {
  /// Démarre [source] : soit un chemin d'asset relatif à `assets/`, soit une
  /// URL `http(s)` (catalogue de méditations distant). Renvoie `true` si la
  /// lecture a réellement pu démarrer (`false` si l'asset/URL est absent ou la
  /// plateforme indisponible — aucune exception).
  Future<bool> play(String source);

  Future<void> pause();
  Future<void> resume();
  Future<void> stop();

  Stream<Duration> get onPosition;
  Stream<Duration> get onDuration;
  Stream<void> get onComplete;

  bool get isPlaying;

  void dispose();
}

/// Implémentation réelle via `package:audioplayers`. Tous les appels plateforme
/// sont protégés : en test (`MissingPluginException`) ou si l'asset n'existe
/// pas encore, [play] renvoie `false` sans jamais lever.
class AudioPlayersMeditationAudio implements MeditationAudio {
  AudioPlayersMeditationAudio() {
    try {
      _player = AudioPlayer();
      _subs.add(_player!.onPositionChanged.listen(_position.add));
      _subs.add(_player!.onDurationChanged.listen(_duration.add));
      _subs.add(
        _player!.onPlayerComplete.listen((_) {
          _playing = false;
          _complete.add(null);
        }),
      );
    } catch (_) {
      _player = null;
    }
  }

  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _subs = [];
  final StreamController<Duration> _position = StreamController.broadcast();
  final StreamController<Duration> _duration = StreamController.broadcast();
  final StreamController<void> _complete = StreamController.broadcast();
  bool _playing = false;

  @override
  Stream<Duration> get onPosition => _position.stream;

  @override
  Stream<Duration> get onDuration => _duration.stream;

  @override
  Stream<void> get onComplete => _complete.stream;

  @override
  bool get isPlaying => _playing;

  @override
  Future<bool> play(String source) async {
    final p = _player;
    if (p == null || source.isEmpty) return false;
    try {
      await p.stop();
      await p.setVolume(0.9);
      final isUrl =
          source.startsWith('http://') || source.startsWith('https://');
      await p.play(isUrl ? UrlSource(source) : AssetSource(source));
      _playing = true;
      return true;
    } catch (_) {
      _playing = false;
      return false; // fichier / URL absent / plateforme absente -> silencieux
    }
  }

  @override
  Future<void> pause() async {
    _playing = false;
    try {
      await _player?.pause();
    } catch (_) {}
  }

  @override
  Future<void> resume() async {
    try {
      await _player?.resume();
      _playing = true;
    } catch (_) {
      _playing = false;
    }
  }

  @override
  Future<void> stop() async {
    _playing = false;
    try {
      await _player?.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _playing = false;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _position.close();
    _duration.close();
    _complete.close();
    try {
      _player?.dispose();
    } catch (_) {}
  }
}
