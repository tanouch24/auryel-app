import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// The app's video_player dependency exports this platform interface transitively;
// the import is only used to install the fake platform in these tests.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:auryel/widgets/wake_video_stage.dart';

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final Map<int, StreamController<VideoEvent>> _events = {};
  final Set<int> loopingPlayers = {};
  final Set<int> playingPlayers = {};
  final List<int> playCalls = [];
  final List<int> pauseCalls = [];
  final List<int> disposeCalls = [];
  int _nextPlayerId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _nextPlayerId++;
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    scheduleMicrotask(() {
      events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(minutes: 1),
          size: const Size(720, 1280),
          rotationCorrection: 0,
        ),
      );
    });
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    if (looping) {
      loopingPlayers.add(playerId);
    } else {
      loopingPlayers.remove(playerId);
    }
  }

  @override
  Future<void> play(int playerId) async {
    playCalls.add(playerId);
    playingPlayers.add(playerId);
    _events[playerId]!.add(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: true,
      ),
    );
  }

  @override
  Future<void> pause(int playerId) async {
    pauseCalls.add(playerId);
    playingPlayers.remove(playerId);
    _events[playerId]!.add(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: false,
      ),
    );
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();

  @override
  Future<void> dispose(int playerId) async {
    disposeCalls.add(playerId);
    await _events.remove(playerId)?.close();
    playingPlayers.remove(playerId);
  }
}

void main() {
  late VideoPlayerPlatform previousPlatform;
  late _FakeVideoPlayerPlatform fakePlatform;

  setUp(() {
    previousPlatform = VideoPlayerPlatform.instance;
    fakePlatform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fakePlatform;
  });

  tearDown(() {
    VideoPlayerPlatform.instance = previousPlatform;
  });

  Future<GlobalKey<WakeVideoStageState>> pumpStage(WidgetTester tester) async {
    final key = GlobalKey<WakeVideoStageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: WakeVideoStage(
          key: key,
          file: File('wake-preview-test.mp4'),
          autoplay: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(key.currentState?.isReady, isTrue);
    return key;
  }

  testWidgets('play starts the preview', (tester) async {
    final key = await pumpStage(tester);

    await key.currentState!.play();

    expect(key.currentState!.isPlaying, isTrue);
    expect(fakePlatform.playCalls, hasLength(1));
  });

  testWidgets('play then pause stops the preview', (tester) async {
    final key = await pumpStage(tester);
    final stage = key.currentState!;

    await stage.play();
    await stage.pause();

    expect(stage.isPlaying, isFalse);
    expect(fakePlatform.pauseCalls, isNotEmpty);
  });

  testWidgets('play pause play resumes the preview', (tester) async {
    final key = await pumpStage(tester);
    final stage = key.currentState!;

    await stage.play();
    await stage.pause();
    await stage.play();

    expect(stage.isPlaying, isTrue);
    expect(fakePlatform.playCalls, hasLength(2));
    expect(fakePlatform.pauseCalls, isNotEmpty);
  });

  testWidgets('looping remains enabled and pause still works', (tester) async {
    final key = await pumpStage(tester);
    final stage = key.currentState!;

    await stage.play();
    await stage.pause();

    expect(fakePlatform.loopingPlayers, contains(0));
    expect(stage.isPlaying, isFalse);
  });

  testWidgets('rapid double toggle settles on the second requested state', (
    tester,
  ) async {
    final key = await pumpStage(tester);
    final stage = key.currentState!;

    await Future.wait([stage.togglePlayback(), stage.togglePlayback()]);

    expect(stage.isPlaying, isFalse);
    expect(fakePlatform.playCalls, hasLength(1));
    expect(fakePlatform.pauseCalls, isNotEmpty);
  });

  testWidgets('leaving the route pauses and disposes the preview', (
    tester,
  ) async {
    final key = await pumpStage(tester);
    await key.currentState!.play();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(fakePlatform.pauseCalls, isNotEmpty);
    expect(fakePlatform.disposeCalls, hasLength(1));
    expect(fakePlatform.playingPlayers, isEmpty);
  });

  testWidgets('back navigation disposes the preview', (tester) async {
    final key = GlobalKey<WakeVideoStageState>();
    late NavigatorState navigator;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            navigator = Navigator.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();
    unawaited(
      navigator.push(
        MaterialPageRoute(
          builder: (_) => WakeVideoStage(
            key: key,
            file: File('wake-preview-test.mp4'),
            autoplay: false,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await key.currentState!.play();

    navigator.pop();
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(fakePlatform.pauseCalls, isNotEmpty);
    expect(fakePlatform.disposeCalls, hasLength(1));
  });
}
