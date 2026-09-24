import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/wake_video.dart';

void main() {
  test('sans jours, conserve le prochain horaire local le même jour', () {
    final now = DateTime(2026, 9, 23, 6, 30);

    expect(
      WakeScheduleDate.nextTarget(now, 7, 0, const {}),
      DateTime(2026, 9, 23, 7),
    );
  });

  test('une heure déjà passée bascule au jour local suivant', () {
    final now = DateTime(2026, 9, 23, 7);

    expect(
      WakeScheduleDate.nextTarget(now, 7, 0, const {}),
      DateTime(2026, 9, 24, 7),
    );
  });

  test('les jours suivent la convention Android dimanche=1 à samedi=7', () {
    // 23 septembre 2026 est un mercredi ; le jour 6 est vendredi.
    final now = DateTime(2026, 9, 23, 20);

    expect(
      WakeScheduleDate.nextTarget(now, 7, 15, const {6}),
      DateTime(2026, 9, 25, 7, 15),
    );
  });

  test('une liste de jours vide représente tous les jours', () {
    final now = DateTime(2026, 9, 23, 20);

    expect(
      WakeScheduleDate.nextTarget(now, 7, 15, const {}),
      DateTime(2026, 9, 24, 7, 15),
    );
  });
}
