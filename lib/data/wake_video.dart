import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Vidéo complète utilisée par le Réveil V2 : image, musique et voix sont
/// dans le même fichier et sont lus par un seul lecteur.
class WakeVideo {
  const WakeVideo({
    required this.id,
    required this.remoteUrl,
    this.localPath,
    this.version,
  });

  final String id;
  final String remoteUrl;
  final String? localPath;
  final String? version;

  bool get hasLocalPath => localPath != null && localPath!.isNotEmpty;

  WakeVideo withLocalPath(String path) => WakeVideo(
    id: id,
    remoteUrl: remoteUrl,
    localPath: path,
    version: version,
  );
}

class WakeVideoCatalog {
  const WakeVideoCatalog._();

  static const WakeVideo pilot = WakeVideo(
    id: 'wake-test-01',
    remoteUrl:
        'https://pub-19c78d4dc57a41849a27c0e73ed231ce.r2.dev/'
        'wake-videos/auryel-reveil-video-test-01.mp4',
  );

  static const List<WakeVideo> active = [pilot];
}

class WakeVideoCache {
  final Directory? directory;
  final HttpClient _client;

  WakeVideoCache({this.directory, HttpClient? client})
    : _client = client ?? HttpClient();

  Future<File?> prepare(WakeVideo video) async {
    try {
      if (video.hasLocalPath) {
        final local = File(video.localPath!);
        if (await _isUsable(local)) return local;
      }
      final directory =
          this.directory ??
          Directory(
            '${(await getApplicationSupportDirectory()).path}/wake-videos',
          );
      await directory.create(recursive: true);
      final file = File('${directory.path}/${video.id}.mp4');
      if (await _isUsable(file)) return file;

      final request = await _client.getUrl(Uri.parse(video.remoteUrl));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) return null;
      final bytes = await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      if (bytes.isEmpty) return null;
      await file.writeAsBytes(bytes, flush: true);
      return await _isUsable(file) ? file : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isUsable(File file) async {
    try {
      return await file.exists() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  void close() {
    _client.close(force: true);
  }
}
