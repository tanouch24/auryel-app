import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Vidéo complète utilisée par le Réveil V2 : image, musique et voix sont
/// dans le même fichier et sont lus par un seul lecteur.
class WakeVideo {
  const WakeVideo({
    required this.id,
    required this.remoteUrl,
    this.title = 'Réveil Auryel',
    this.durationSeconds,
    this.sortOrder = 0,
    this.localPath,
    this.version,
  });

  final String id;
  final String remoteUrl;
  final String title;
  final int? durationSeconds;
  final int sortOrder;
  final String? localPath;
  final String? version;

  bool get hasLocalPath => localPath != null && localPath!.isNotEmpty;

  bool get isPilot => remoteUrl.endsWith(
    '/wake-videos/auryel-reveil-video-test-01.mp4',
  );

  WakeVideo withLocalPath(String path) => WakeVideo(
    id: id,
    remoteUrl: remoteUrl,
    title: title,
    durationSeconds: durationSeconds,
    sortOrder: sortOrder,
    localPath: path,
    version: version,
  );

  static WakeVideo? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'] is String ? (json['id'] as String).trim() : '';
    final url = json['video_url'] is String
        ? (json['video_url'] as String).trim()
        : '';
    if (id.isEmpty ||
        !(url.startsWith('https://') || url.startsWith('http://'))) {
      return null;
    }
    final rawTitle = json['title'] is String
        ? (json['title'] as String).trim()
        : '';
    return WakeVideo(
      id: id,
      remoteUrl: url,
      title: rawTitle.isEmpty ? 'Réveil Auryel' : rawTitle,
      durationSeconds: json['duration_seconds'] is num
          ? (json['duration_seconds'] as num).toInt()
          : null,
      sortOrder: json['sort_order'] is num
          ? (json['sort_order'] as num).toInt()
          : 0,
      version: json['version'] is String ? json['version'] as String : null,
    );
  }

  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'video_url': remoteUrl,
    'title': title,
    if (durationSeconds != null) 'duration_seconds': durationSeconds,
    'sort_order': sortOrder,
    if (version != null) 'version': version,
  };
}

class WakeVideoCatalog {
  const WakeVideoCatalog._();

  static const pilotRemoteUrl =
      'https://pub-19c78d4dc57a41849a27c0e73ed231ce.r2.dev/'
      'wake-videos/auryel-reveil-video-test-01.mp4';

  static const WakeVideo pilot = WakeVideo(
    id: 'wake-test-01',
    remoteUrl: pilotRemoteUrl,
    title: 'Réveil Auryel — pilote',
  );

  static const List<WakeVideo> active = [pilot];
}

/// Sélection déterministe du contenu du jour. Le catalogue est trié par le
/// serveur ; le résultat dépend uniquement de la date et du catalogue reçu.
class WakeVideoDailySelection {
  const WakeVideoDailySelection._();

  static WakeVideo pick(List<WakeVideo> catalog, DateTime date) {
    final realVideos = catalog.where((video) => !video.isPilot).toList();
    final source = realVideos.isNotEmpty ? realVideos : catalog;
    final items = [...source]
      ..sort((a, b) {
        final order = a.sortOrder.compareTo(b.sortOrder);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    if (items.isEmpty) return WakeVideoCatalog.pilot;
    if (items.length == 1) return items.first;

    final index = _indexFor(date, items.length);
    final previousIndex = _indexFor(
      date.subtract(const Duration(days: 1)),
      items.length,
    );
    final adjusted = index == previousIndex
        ? (index + 1) % items.length
        : index;
    return items[adjusted];
  }

  static int _indexFor(DateTime date, int length) {
    final day =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    var hash = 0;
    for (final code in day.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash % length;
  }
}

class WakeScheduleDate {
  const WakeScheduleDate._();

  static DateTime nextTarget(
    DateTime now,
    int hour,
    int minute,
    Set<int> days,
  ) {
    var candidate = DateTime(now.year, now.month, now.day, hour, minute);
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    if (days.isEmpty) return candidate;
    for (var i = 0; i < 8; i++) {
      final androidDay = candidate.weekday == DateTime.sunday
          ? 1
          : candidate.weekday + 1;
      if (days.contains(androidDay)) return candidate;
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }
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
