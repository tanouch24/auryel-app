import 'api_client.dart';

class WellbeingEbook {
  const WellbeingEbook({
    required this.id,
    required this.slug,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.coverUrl,
    required this.pdfUrl,
    required this.publicationDate,
    required this.monthLabel,
    required this.version,
    required this.active,
    required this.featured,
  });

  final int id;
  final String slug;
  final String title;
  final String subtitle;
  final String? description;
  final String? coverUrl;
  final String? pdfUrl;
  final String? publicationDate;
  final String? monthLabel;
  final int version;
  final bool active;
  final bool featured;

  factory WellbeingEbook.fromJson(Map<String, dynamic> json) => WellbeingEbook(
    id: _int(json['id']),
    slug: (json['slug'] ?? '').toString(),
    title: (json['title'] ?? '').toString(),
    subtitle: (json['subtitle'] ?? '').toString(),
    description: _nullable(json['description']),
    coverUrl: _nullable(json['cover_url']),
    pdfUrl: _nullable(json['pdf_url']),
    publicationDate: _nullable(json['publication_date']),
    monthLabel: _nullable(json['month_label']),
    version: _int(json['version']),
    active: json['active'] != false,
    featured: json['featured'] == true,
  );
}

class WellbeingEbooksApi {
  WellbeingEbooksApi(this._client);
  final ApiClient _client;

  Future<List<WellbeingEbook>> getCatalog(String bearer) async {
    final json = await _client.getJson(
      '/api/app/wellbeing-ebooks',
      bearer: bearer,
    );
    final raw = json['ebooks'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(WellbeingEbook.fromJson)
        .toList(growable: false);
  }
}

String? _nullable(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
