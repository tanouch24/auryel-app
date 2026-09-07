import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// Fine abstraction du lecteur audio pour les présentations conseiller.
/// Un SEUL exemplaire vit dans `ConsultationScreen` (jamais un par conseiller).
/// Isolée pour être remplaçable en test (aucun canal plateforme, aucun timer).
abstract class AdvisorAudio {
  /// Joue [assetPath] (chemin relatif à `assets/`, convention `AssetSource`)
  /// avec un fondu d'entrée doux de [fadeIn] (0 = pas de fondu). Un appel
  /// remplace la source précédente : jamais deux voix en même temps.
  Future<void> play(String assetPath, {Duration fadeIn});

  /// Arrête immédiatement et annule tout fondu en cours.
  Future<void> stop();

  void dispose();
}

/// Implémentation réelle via `package:audioplayers`. Le fondu est géré ici par
/// un `Timer.periodic` interne, démarré UNIQUEMENT si la lecture a réellement
/// commencé (donc jamais en environnement de test où le canal plateforme est
/// absent) et annulé par [stop] / [dispose].
class AudioPlayersAdvisorAudio implements AdvisorAudio {
  AudioPlayersAdvisorAudio() {
    try {
      _player = AudioPlayer();
    } catch (_) {
      _player = null;
    }
  }

  AudioPlayer? _player;
  Timer? _fade;
  static const double _target = 0.9;

  void _cancelFade() {
    _fade?.cancel();
    _fade = null;
  }

  @override
  Future<void> play(String assetPath, {Duration fadeIn = Duration.zero}) async {
    _cancelFade();
    final p = _player;
    if (p == null) return;
    try {
      await p.stop();
      await p.setVolume(fadeIn > Duration.zero ? 0 : _target);
      await p.play(AssetSource(assetPath));
    } catch (_) {
      return; // plateforme absente / fichier illisible -> silencieux, aucun timer
    }
    if (fadeIn <= Duration.zero) return;
    const steps = 5;
    final tick = Duration(
      milliseconds: (fadeIn.inMilliseconds ~/ steps).clamp(20, 200),
    );
    var i = 0;
    _fade = Timer.periodic(tick, (timer) async {
      i++;
      final v = (_target * i / steps).clamp(0.0, _target);
      try {
        await _player?.setVolume(v);
      } catch (_) {
        /* ignore */
      }
      if (i >= steps) {
        timer.cancel();
        _fade = null;
      }
    });
  }

  @override
  Future<void> stop() async {
    _cancelFade();
    try {
      await _player?.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _cancelFade();
    try {
      _player?.dispose();
    } catch (_) {}
  }
}
