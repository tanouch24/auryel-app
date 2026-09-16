import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/wake_video.dart';
import 'package:auryel/screens/onboarding/wake_onboarding_screen.dart';

class _NoNetworkWakeCache extends WakeVideoCache {
  @override
  Future<File?> prepare(WakeVideo video) async => null;
}

Widget _host({VoidCallback? onFinished, NavigatorObserver? observer}) => MaterialApp(
  navigatorObservers: observer == null ? const [] : [observer],
  home: WakeOnboardingScreen(
    cache: _NoNetworkWakeCache(),
    onFinished: onFinished,
  ),
);

void main() {
  testWidgets('nouvel utilisateur voit la découverte, fallback et CTA', (t) async {
    await t.pumpWidget(_host());
    await t.pump();
    await t.ensureVisible(find.byKey(const Key('wake-onboarding-configure')));
    expect(
      t.widget<ElevatedButton>(find.byKey(const Key('wake-onboarding-configure'))).onPressed,
      isNotNull,
    );
    expect(find.text('Réveillez-vous avec Auryel'), findsOneWidget);
    expect(find.byKey(const Key('wake-onboarding-configure')), findsOneWidget);
    expect(find.byKey(const Key('wake-onboarding-later')), findsOneWidget);
    expect(find.textContaining('Étoile'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('Plus tard poursuit le parcours sans effet Réveil', (t) async {
    var finished = false;
    await t.pumpWidget(_host(onFinished: () => finished = true));
    await t.pump();
    await t.tap(find.byKey(const Key('wake-onboarding-later')));
    await t.pump();
    expect(finished, isTrue);
  });

  testWidgets('Configurer mon réveil ouvre la vraie configuration', (t) async {
    final observer = _PushObserver();
    await t.pumpWidget(_host(observer: observer));
    await t.pump();
    await t.ensureVisible(find.byKey(const Key('wake-onboarding-configure')));
    final configure = t.widget<ElevatedButton>(
      find.byKey(const Key('wake-onboarding-configure')),
    );
    configure.onPressed!.call();
    await t.pump(const Duration(milliseconds: 600));
    expect(observer.pushes, 2);
    expect(t.takeException(), isNull);
  });
}

class _PushObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}
