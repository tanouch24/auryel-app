import 'package:flutter_test/flutter_test.dart';
import 'package:auryel/ads/ad_service.dart';

void main() {
  test('prépare uniquement des identifiants SSV non sensibles', () {
    final options = rewardedSsvOptions(
      userId: 'user-uuid',
      customData: 'session-uuid',
    );
    expect(options.userId, 'user-uuid');
    expect(options.customData, 'session-uuid');
  });
}
