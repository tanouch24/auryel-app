import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/meditation_audio.dart';

// ===========================================================================
// CORRECTIF « double dispose » — en conditions réelles (Samsung), le feed
// méditation partage UN lecteur `AudioPlayersMeditationAudio` entre le slot
// qui le crée et l'écran qui le consomme (`audioOverride`). Si les deux le
// disposaient, le lecteur `audioplayers` réel plantait avec une
// `PlatformException`/`AudioPlayer has been disposed` NON RATTRAPÉE
// (asynchrone, un `try {}` synchrone autour d'un appel non attendu ne
// l'attrape jamais). `dispose()` doit désormais être idempotent ET ne
// jamais laisser fuiter une erreur asynchrone.
// ===========================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'dispose() appelé deux fois ne lève JAMAIS (idempotent, aucune erreur '
    'asynchrone non rattrapée)',
    () async {
      final audio = AudioPlayersMeditationAudio();
      audio.dispose();
      audio.dispose(); // 2ᵉ appel — ne doit jamais planter.
      // Laisse une chance à une éventuelle erreur asynchrone non rattrapée
      // de se manifester avant la fin du test (le framework de test échoue
      // sur toute exception de zone non gérée).
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(true, isTrue); // atteint ce point -> aucune exception échappée
    },
  );

  test('play() après dispose() ne lève jamais (best-effort, renvoie false)', () async {
    final audio = AudioPlayersMeditationAudio();
    audio.dispose();
    final ok = await audio.play('https://cdn.auryel.app/x.mp3');
    expect(ok, isFalse);
  });
}
