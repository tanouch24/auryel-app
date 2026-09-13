import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/wake_message.dart';
import 'package:auryel/data/wake_message_catalog.dart';
import 'package:auryel/data/wake_message_selector.dart';

List<WakeMessage> _catalog(int n) =>
    List.generate(n, (i) => WakeMessage(id: 'm$i', text: 'Texte $i'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('WakeMessage.tryFromJson', () {
    test('accepte un JSON complet (avec audio_url)', () {
      final m = WakeMessage.tryFromJson({
        'id': 'abc',
        'text': 'Bonjour',
        'audio_url': 'https://cdn.auryel.app/wake/abc.mp3',
      });
      expect(m, isNotNull);
      expect(m!.id, 'abc');
      expect(m.text, 'Bonjour');
      expect(m.audioUrl, 'https://cdn.auryel.app/wake/abc.mp3');
    });

    test('audio_url absent/null -> audioUrl null (repli TTS attendu)', () {
      final m = WakeMessage.tryFromJson({'id': 'abc', 'text': 'Bonjour'});
      expect(m!.audioUrl, isNull);
    });

    test('id ou text manquant/vide -> null (entrée ignorée, jamais de crash)', () {
      expect(WakeMessage.tryFromJson({'text': 'Bonjour'}), isNull);
      expect(WakeMessage.tryFromJson({'id': 'abc'}), isNull);
      expect(WakeMessage.tryFromJson({'id': '  ', 'text': 'x'}), isNull);
      expect(WakeMessage.tryFromJson({'id': 'abc', 'text': ''}), isNull);
    });
  });

  group('WakeMessageCatalog (repli embarqué)', () {
    test('au moins 10 messages, tous avec id + texte non vides', () {
      expect(WakeMessageCatalog.items.length, greaterThanOrEqualTo(10));
      for (final m in WakeMessageCatalog.items) {
        expect(m.id, isNotEmpty);
        expect(m.text, isNotEmpty);
      }
    });

    test('aucun identifiant dupliqué', () {
      final ids = WakeMessageCatalog.items.map((m) => m.id).toSet();
      expect(ids.length, WakeMessageCatalog.items.length);
    });
  });

  group('WakeMessageHistory', () {
    test('vide au départ', () async {
      final h = WakeMessageHistory(prefs: await SharedPreferences.getInstance());
      expect(await h.recent(), isEmpty);
    });

    test('push ajoute en tête, sans doublon', () async {
      final h = WakeMessageHistory(prefs: await SharedPreferences.getInstance());
      await h.push('a');
      await h.push('b');
      await h.push('a'); // déjà présent -> remonte en tête, pas de doublon
      expect(await h.recent(), ['a', 'b']);
    });

    test('conserve au plus `keep` identifiants (défaut ~20)', () async {
      final h = WakeMessageHistory(
        prefs: await SharedPreferences.getInstance(),
        keep: 3,
      );
      for (final id in ['a', 'b', 'c', 'd']) {
        await h.push(id);
      }
      expect(await h.recent(), ['d', 'c', 'b']);
    });

    test('push d\'un identifiant vide -> ignoré', () async {
      final h = WakeMessageHistory(prefs: await SharedPreferences.getInstance());
      await h.push('');
      expect(await h.recent(), isEmpty);
    });
  });

  group('WakeMessageSelector.choose (pur)', () {
    test('catalogue vide -> null', () {
      final s = WakeMessageSelector(random: Random(0));
      expect(s.choose(const []), isNull);
    });

    test('1 seul message -> toujours celui-ci', () {
      final s = WakeMessageSelector(random: Random(0));
      final only = _catalog(1);
      expect(s.choose(only), only.first);
    });

    test('exclut les identifiants récents tant qu\'il reste un candidat', () {
      final s = WakeMessageSelector(random: Random(0));
      final catalog = _catalog(5);
      for (var trial = 0; trial < 30; trial++) {
        final picked = s.choose(catalog, avoid: ['m0', 'm1', 'm2', 'm3']);
        expect(picked!.id, 'm4');
      }
    });

    test(
      'catalogue trop petit (<= historique) -> dégrade proprement : autorise '
      'la répétition plutôt que de renvoyer null',
      () {
        final s = WakeMessageSelector(random: Random(0));
        final catalog = _catalog(3);
        final picked = s.choose(catalog, avoid: ['m0', 'm1', 'm2']);
        expect(picked, isNotNull);
        expect(catalog.map((m) => m.id), contains(picked!.id));
      },
    );
  });

  group('WakeMessageSelector.pick (avec historique)', () {
    test('anti-répétition : ne rejoue pas les ~20 derniers tant que possible', () async {
      final history = WakeMessageHistory(
        prefs: await SharedPreferences.getInstance(),
        keep: 20,
      );
      final selector = WakeMessageSelector(random: Random(1), history: history);
      final catalog = _catalog(25);

      final picked = <String>{};
      for (var i = 0; i < 20; i++) {
        final m = await selector.pick(catalog);
        expect(m, isNotNull);
        expect(
          picked.contains(m!.id),
          isFalse,
          reason: 'répétition avant que les 20 derniers soient épuisés',
        );
        picked.add(m.id);
      }
    });

    test('met à jour l\'historique après chaque sélection', () async {
      final history = WakeMessageHistory(
        prefs: await SharedPreferences.getInstance(),
      );
      final selector = WakeMessageSelector(random: Random(2), history: history);
      final catalog = _catalog(5);

      final first = await selector.pick(catalog);
      expect(await history.recent(), [first!.id]);
    });

    test('catalogue vide -> null, jamais d\'exception', () async {
      final selector = WakeMessageSelector(
        random: Random(3),
        history: WakeMessageHistory(prefs: await SharedPreferences.getInstance()),
      );
      expect(await selector.pick(const []), isNull);
    });
  });
}
