import 'dart:async';
import 'dart:io' show Platform;

import '../api/api_client.dart';
import 'package:flutter/widgets.dart';

/// Minimal first-party analytics client.
///
/// Analytics is deliberately best-effort: it has a short timeout, no retry
/// loop, no user-visible error and can never block a product action.
class FirstPartyAnalytics {
  FirstPartyAnalytics({
    required this.api,
    required this.tokenProvider,
  });

  final ApiClient api;
  final Future<String?> Function() tokenProvider;
  bool _sessionStarted = false;

  String get platform {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'web';
  }

  Future<void> log(
    String eventName, {
    Map<String, dynamic> properties = const <String, dynamic>{},
    String? idempotencyKey,
  }) async {
    try {
      final token = await tokenProvider().timeout(const Duration(seconds: 2));
      if (token == null || token.isEmpty) return;
      await api
          .postJson(
            '/api/app/analytics/events',
            <String, dynamic>{
              'event_name': eventName,
              'platform': platform,
              if (properties.isNotEmpty) 'properties': properties,
              // ignore: use_null_aware_elements
              if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
            },
            bearer: token,
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Analytics must never affect authentication, navigation, billing or UX.
    }
  }

  Future<void> logSessionStarted() async {
    if (_sessionStarted) return;
    _sessionStarted = true;
    await log('app_opened');
    await log('session_started');
  }
}

class FirstPartyAnalyticsScope extends InheritedWidget {
  const FirstPartyAnalyticsScope({
    super.key,
    required this.analytics,
    required super.child,
  });

  final FirstPartyAnalytics analytics;

  static FirstPartyAnalytics? maybeReadOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FirstPartyAnalyticsScope>()?.analytics;

  @override
  bool updateShouldNotify(FirstPartyAnalyticsScope oldWidget) =>
      oldWidget.analytics != analytics;
}
