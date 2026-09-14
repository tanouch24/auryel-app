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
  /// CORRECTIF « lecture synchronisée » (feed méditation) — prépare [source]
  /// (charge/définit la source) SANS démarrer la lecture, pour qu'un [play]
  /// ultérieur sur la MÊME source démarre quasi instantanément (pas de
  /// nouvelle résolution réseau à ce moment-là). Best-effort : une erreur ici
  /// n'empêche jamais [play] de fonctionner normalement ensuite (il refera
  /// alors un chargement complet).
  Future<void> prepare(String source);

  /// Démarre [source] : soit un chemin d'asset relatif à `assets/`, soit une
  /// URL `http(s)` (catalogue de méditations distant). Si [source] a déjà été
  /// préparée via [prepare], démarre depuis cette préparation (rapide) au
  /// lieu de relancer un chargement complet. Renvoie `true` si la lecture a
  /// réellement pu démarrer (`false` si l'asset/URL est absent ou la
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

  /// Source déjà préparée via [prepare] (source définie côté plateforme,
  /// prête à démarrer) — `null` tant qu'aucune préparation n'est en attente
  /// de consommation par [play].
  String? _preparedSource;

  @override
  Stream<Duration> get onPosition => _position.stream;

  @override
  Stream<Duration> get onDuration => _duration.stream;

  @override
  Stream<void> get onComplete => _complete.stream;

  @override
  bool get isPlaying => _playing;

  @override
  Future<void> prepare(String source) async {
    final p = _player;
    if (p == null || source.isEmpty) return;
    try {
      final isUrl =
          source.startsWith('http://') || source.startsWith('https://');
      // `setSourceUrl`/`setSourceAsset` DÉFINISSENT la source (le flux
      // commence à être bufferisé côté plateforme) SANS démarrer la lecture —
      // idiome documenté par `audioplayers` pour réduire la latence d'un
      // `resume()` ultérieur. Jamais appelé pendant que CETTE instance joue
      // déjà autre chose (une instance = un seul slot du feed).
      if (isUrl) {
        await p.setSourceUrl(source);
      } else {
        await p.setSourceAsset(source);
      }
      await p.setVolume(0.9);
      _preparedSource = source;
    } catch (_) {
      // Échec de préparation anticipée -> `play()` refera un chargement
      // complet le moment venu, jamais bloquant.
      _preparedSource = null;
    }
  }

  @override
  Future<bool> play(String source) async {
    final p = _player;
    if (p == null || source.isEmpty) return false;
    try {
      if (_preparedSource == source) {
        // CORRECTIF « lecture synchronisée » — source déjà préparée par
        // [prepare] : `resume()` démarre quasi instantanément (aucune
        // nouvelle résolution réseau à cet instant), c'est tout l'intérêt du
        // préchargement en avance du feed méditation.
        await p.resume();
      } else {
        await p.stop();
        await p.setVolume(0.9);
        final isUrl =
            source.startsWith('http://') || source.startsWith('https://');
        await p.play(isUrl ? UrlSource(source) : AssetSource(source));
      }
      _preparedSource = null;
      _playing = true;
      return true;
    } catch (_) {
      _playing = false;
      _preparedSource = null;
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
