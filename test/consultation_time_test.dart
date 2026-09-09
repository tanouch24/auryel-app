import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/consultation.dart';
import 'package:auryel/state/consultation_controller.dart';

// ===========================================================================
// TIMER-D.1 — modèle temps + formatage. SOURCE DE VÉRITÉ = bloc `time`,
// jamais `expires_at - now`.
// ===========================================================================

Map<String, dynamic> _stateBody({
  Map<String, dynamic>? time,
  Map<String, dynamic>? consultation,
  bool includeTime = true,
}) => {
  'consultation': consultation,
  if (includeTime && time != null) 'time': time,
  'quota': {
    'is_premium': true,
    'monthly_limit': 8,
    'monthly_used': 1,
    'monthly_remaining': 7,
    'earned_available': 0,
    'first_free_available': false,
    'period_start': '2026-08-01T00:00:00Z',
    'period_end': '2026-09-01T00:00:00Z',
  },
};

void main() {
  group('A. Parsing GET /state avec bloc time complet', () {
    test('parse consultation + time + quota', () {
      final r = ConsultationStateResponse.fromJson(
        _stateBody(
          consultation: {
            'id': 'c-1',
            'advisor_id': 'selena',
            'started_at': '2026-09-01T10:00:00Z',
            'expires_at': '2026-09-01T12:00:00Z',
            'seconds_remaining': 32400,
            'credit_source': 'time',
            'opened_now': false,
          },
          time: {
            'first_free_remaining_seconds': 3600,
            'premium_remaining_seconds': 28800,
            'purchased_remaining_seconds': 0,
            'total_remaining_seconds': 32400,
            'window_active': true,
            'window_expires_at': '2026-09-01T10:05:00Z',
          },
        ),
      );
      expect(r.consultation!.creditSource, 'time');
      expect(r.time, isNotNull);
      expect(r.time!.totalRemainingSeconds, 32400);
      expect(r.quota.monthlyLimit, 8);
    });
  });

  group('B/C/D/E. Buckets', () {
    test('B. premier free : first_free=3600, total=3600', () {
      final t = ConsultationTimeState.fromJson({
        'first_free_remaining_seconds': 3600,
        'premium_remaining_seconds': 0,
        'purchased_remaining_seconds': 0,
        'total_remaining_seconds': 3600,
        'window_active': true,
        'window_expires_at': null,
      });
      expect(t.firstFreeRemainingSeconds, 3600);
      expect(t.totalRemainingSeconds, 3600);
      expect(t.hasTime, isTrue);
    });

    test('C. Premium : premium=28800, total=28800', () {
      final t = ConsultationTimeState.fromJson({
        'first_free_remaining_seconds': 0,
        'premium_remaining_seconds': 28800,
        'purchased_remaining_seconds': 0,
        'total_remaining_seconds': 28800,
        'window_active': false,
        'window_expires_at': null,
      });
      expect(t.premiumRemainingSeconds, 28800);
      expect(t.totalRemainingSeconds, 28800);
    });

    test('D. purchased exposé', () {
      final t = ConsultationTimeState.fromJson({
        'first_free_remaining_seconds': 0,
        'premium_remaining_seconds': 0,
        'purchased_remaining_seconds': 7200,
        'total_remaining_seconds': 7200,
        'window_active': false,
        'window_expires_at': null,
      });
      expect(t.purchasedRemainingSeconds, 7200);
    });

    test('E. total absent -> somme des buckets ; négatifs clampés à 0', () {
      final t = ConsultationTimeState.fromJson({
        'first_free_remaining_seconds': 100,
        'premium_remaining_seconds': 200,
        'purchased_remaining_seconds': -50, // clamp -> 0
        'window_active': false,
      });
      expect(t.purchasedRemainingSeconds, 0);
      expect(t.totalRemainingSeconds, 300); // 100 + 200 + 0
      expect(t.bucketSum, 300);
    });

    test('parsing robuste : valeurs string / num / null', () {
      final t = ConsultationTimeState.fromJson({
        'first_free_remaining_seconds': '900',
        'premium_remaining_seconds': 60.0,
        'purchased_remaining_seconds': null,
        'total_remaining_seconds': '960',
        'window_active': 'yes', // != true -> false
      });
      expect(t.firstFreeRemainingSeconds, 900);
      expect(t.premiumRemainingSeconds, 60);
      expect(t.purchasedRemainingSeconds, 0);
      expect(t.totalRemainingSeconds, 960);
      expect(t.windowActive, isFalse);
    });
  });

  group('F/G. Fenêtre active', () {
    test('F. window_active true + window_expires_at parsé', () {
      final t = ConsultationTimeState.fromJson({
        'first_free_remaining_seconds': 0,
        'premium_remaining_seconds': 10000,
        'purchased_remaining_seconds': 0,
        'total_remaining_seconds': 10000,
        'window_active': true,
        'window_expires_at': '2026-09-01T10:05:00Z',
      });
      expect(t.windowActive, isTrue);
      expect(t.windowExpiresAt, DateTime.utc(2026, 9, 1, 10, 5));
    });

    test('G. window_active false : historique/temps toujours exploitables', () {
      final t = ConsultationTimeState.fromJson({
        'first_free_remaining_seconds': 0,
        'premium_remaining_seconds': 10000,
        'purchased_remaining_seconds': 0,
        'total_remaining_seconds': 10000,
        'window_active': false,
        'window_expires_at': null,
      });
      expect(t.windowActive, isFalse);
      expect(t.windowExpiresAt, isNull);
      expect(
        t.hasTime,
        isTrue,
      ); // du temps reste, la consultation n'est pas finie
    });
  });

  group('H. Temps gagné (earned_remaining_seconds)', () {
    test('11 — earned_remaining_seconds parsé', () {
      final t = ConsultationTimeState.fromJson({
        'first_free_remaining_seconds': 0,
        'premium_remaining_seconds': 0,
        'earned_remaining_seconds': 900,
        'purchased_remaining_seconds': 0,
        'total_remaining_seconds': 900,
        'window_active': false,
      });
      expect(t.earnedRemainingSeconds, 900);
      expect(t.totalRemainingSeconds, 900);
    });

    test('12 — champ absent -> 0 (compat backend ancien)', () {
      final t = ConsultationTimeState.fromJson({
        'first_free_remaining_seconds': 0,
        'premium_remaining_seconds': 1200,
        'purchased_remaining_seconds': 0,
        'total_remaining_seconds': 1200,
        'window_active': false,
      });
      expect(t.earnedRemainingSeconds, 0);
      expect(ConsultationTimeState.empty.earnedRemainingSeconds, 0);
    });

    test(
      '13 — bucketSum inclut earned ; total absent -> somme des 4 buckets',
      () {
        final t = ConsultationTimeState.fromJson({
          'first_free_remaining_seconds': 100,
          'premium_remaining_seconds': 200,
          'earned_remaining_seconds': 300,
          'purchased_remaining_seconds': 400,
          'window_active': false,
        });
        expect(t.bucketSum, 1000);
        expect(t.totalRemainingSeconds, 1000);
      },
    );

    test('earned négatif clampé à 0', () {
      final t = ConsultationTimeState.fromJson({
        'first_free_remaining_seconds': 0,
        'premium_remaining_seconds': 0,
        'earned_remaining_seconds': -50,
        'purchased_remaining_seconds': 0,
        'window_active': false,
      });
      expect(t.earnedRemainingSeconds, 0);
    });
  });

  group('N. Backend ANCIEN sans bloc time : aucun crash', () {
    test('maybeFromJson(null / non-objet) -> null', () {
      expect(ConsultationTimeState.maybeFromJson(null), isNull);
      expect(ConsultationTimeState.maybeFromJson('nope'), isNull);
      expect(ConsultationTimeState.maybeFromJson(42), isNull);
    });

    test(
      'ConsultationStateResponse sans time -> time == null, pas d\'exception',
      () {
        final r = ConsultationStateResponse.fromJson(
          _stateBody(
            includeTime: false,
            consultation: {
              'id': 'c',
              'advisor_id': 'selena',
              'seconds_remaining': 5400, // le backend ancien le renvoie
              'credit_source': 'monthly',
            },
          ),
        );
        expect(r.time, isNull);
        expect(r.consultation!.secondsRemaining, 5400);
      },
    );
  });

  group('O. Quota shim : monthly_limit=8 != 8 consultations', () {
    test('la valeur 8 est parsée mais ne représente pas un compteur', () {
      final q = QuotaDto.fromJson({
        'is_premium': true,
        'monthly_limit': 8,
        'monthly_used': 2,
        'monthly_remaining': 6,
      });
      // parsé pour compat écran, mais l'accès dépend du TEMPS (voir contrôleur).
      expect(q.monthlyLimit, 8);
      expect(q.monthlyRemaining, 6);
    });
  });

  group('P. Formatage du portefeuille de temps', () {
    test('exemples du contrat', () {
      String f(int s) => ConsultationController.formatTotalTime(s);
      expect(f(28800), '8 h');
      expect(f(27720), '7 h 42 min');
      expect(f(3600), '1 h');
      expect(f(3900), '1 h 05 min');
      expect(f(3300), '55 min');
      expect(f(300), '5 min');
      expect(f(30), '< 1 min');
      expect(f(0), '0 min');
      expect(f(-120), '0 min');
    });
  });
}
