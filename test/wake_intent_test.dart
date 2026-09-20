import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/wake_video.dart';

void main() {
  test('wake intent reconstructs the scheduled snapshot exactly', () {
    final video = WakeVideo.tryFromJson({
      'id': 'wake-011-id',
      'video_url': 'https://cdn.example/wake-011.mp4',
      'title': 'Auryel wake 011',
    });

    expect(video?.id, 'wake-011-id');
    expect(video?.remoteUrl, 'https://cdn.example/wake-011.mp4');
    expect(video?.title, 'Auryel wake 011');
  });

  test('malformed wake intent is ignored safely', () {
    final video = WakeVideo.tryFromJson({
      'id': null,
      'video_url': null,
      'title': 'invalid',
    });

    expect(video, isNull);
  });
}
