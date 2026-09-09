// Champs privés alimentés par des paramètres nommés publics -> initializing
// formal impossible sans exposer `_bundle` / `_seed` (même parti pris que
// purchase_controller.dart).
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// Une « Pensée du jour » du pack officiel Auryel (100 entrées figées dans
/// `assets/pensees/`). Contenu 100 % local : aucune API, aucun appel LLM,
/// coût d'exploitation nul.
///
/// `publishDate` est un DÉTAIL INTERNE (rotation + nom de fichier) : il ne doit
/// JAMAIS être affiché dans l'UI ni sur un visuel partagé.
@immutable
class DailyThought {
  const DailyThought({
    required this.id,
    required this.publishDate,
    required this.phrase,
    required this.interpretation,
    required this.imageAsset,
    this.imageUrl,
  });

  final int id;
  final DateTime publishDate;
  final String phrase;
  final String interpretation;

  /// Chemin d'asset du visuel WEBP final (1080×1920). Le visuel contient DÉJÀ
  /// la phrase + l'interprétation + le design premium ; il ne porte AUCUNE date.
  /// Vide (`''`) pour une pensée servie par le backend (pas d'asset embarqué) —
  /// l'aperçu partageable retombe alors sur [imageUrl] puis sur du texte seul.
  final String imageAsset;

  /// URL distante du visuel `daily_publication` quand la pensée vient du
  /// backend. `null` pour le pack embarqué (qui utilise [imageAsset]).
  final String? imageUrl;

  factory DailyThought.fromJson(Map<String, dynamic> j) => DailyThought(
    id: (j['id'] as num).toInt(),
    publishDate: DateTime.parse(j['publish_date'] as String),
    phrase: (j['phrase'] as String).trim(),
    interpretation: (j['interpretation'] as String).trim(),
    imageAsset: 'assets/pensees/${j['image_webp']}',
  );

  /// Parsing TOLÉRANT d'une pensée servie par `GET /api/app/content/today`
  /// (`daily_thought`). Renvoie `null` si `phrase` ou `interpretation` manque /
  /// est vide — le contenu du jour est nullable côté backend. `publish_date`,
  /// `id`, `image_url` sont optionnels.
  static DailyThought? tryFromServerJson(Map<String, dynamic> j) {
    final phrase = (j['phrase'] is String)
        ? (j['phrase'] as String).trim()
        : '';
    final interp = (j['interpretation'] is String)
        ? (j['interpretation'] as String).trim()
        : '';
    if (phrase.isEmpty || interp.isEmpty) return null;
    final rawId = j['id'];
    final rawDate = j['publish_date'];
    final img = j['image_url'];
    return DailyThought(
      id: rawId is num ? rawId.toInt() : (int.tryParse('$rawId') ?? 0),
      publishDate: (rawDate is String && rawDate.isNotEmpty)
          ? (DateTime.tryParse(rawDate) ?? DateTime.now())
          : DateTime.now(),
      phrase: phrase,
      interpretation: interp,
      imageAsset: '',
      imageUrl: (img is String && img.isNotEmpty) ? img : null,
    );
  }

  /// Découpe la phrase en (début, fin dorée). La fin dorée est un SUFFIXE EXACT
  /// de la phrase (le texte n'est jamais modifié) : `lead + accent == phrase`.
  /// Sert au rendu de la phrase sur la Home, en cohérence avec le visuel.
  ({String lead, String accent}) splitAccent() {
    final toks = phrase.split(' ');
    if (toks.length < 3) return (lead: '', accent: phrase);

    // 1) chute après la dernière virgule de la seconde moitié.
    for (var j = toks.length - 2; j >= (toks.length + 1) ~/ 2; j--) {
      if (toks[j].endsWith(',')) {
        final tail = toks.sublist(j + 1);
        if (tail.length >= 2 && tail.length <= 6) {
          return (
            lead: toks.sublist(0, j + 1).join(' '),
            accent: tail.join(' '),
          );
        }
      }
    }

    // 2) sinon : 2..5 derniers mots, en évitant de commencer sur un mot faible.
    const weak = {
      'le',
      'la',
      'les',
      'un',
      'une',
      'de',
      'du',
      'des',
      'à',
      'au',
      'aux',
      'ce',
      'ces',
      'et',
      'ou',
      'ni',
      'qui',
      'que',
      'dont',
      'ne',
      'pas',
      'plus',
      'y',
      'en',
      'se',
      'te',
      'si',
      'car',
      'mais',
      'ta',
      'ton',
      'tes',
      'ma',
      'mon',
      'mes',
      'sa',
      'son',
      'ses',
      'encore',
      'comme',
      'leur',
      'leurs',
    };
    String norm(String w) =>
        w.replaceAll(RegExp(r'^[’\x27"«»…-]+|[,;:.!?]+$'), '').toLowerCase();
    final floor = toks.length < 8 ? 2 : 3;
    var k = floor;
    for (var i = 2; i <= (toks.length - 1).clamp(2, 6); i++) {
      if (!weak.contains(norm(toks[toks.length - i]))) {
        k = i;
        break;
      }
    }
    if (k >= toks.length) k = toks.length - 1;
    return (
      lead: toks.sublist(0, toks.length - k).join(' '),
      accent: toks.sublist(toks.length - k).join(' '),
    );
  }
}

/// Source locale des 100 pensées + sélection de la pensée du jour.
///
/// Zéro dépendance réseau. `DailyThoughtRepository()` lit
/// `assets/pensees/pensees_100_site.json`. Injecter [bundle] (tests) ou [seed]
/// (tests unitaires) pour éviter l'accès aux assets réels.
class DailyThoughtRepository {
  DailyThoughtRepository({AssetBundle? bundle, List<DailyThought>? seed})
    : _bundle = bundle,
      _seed = seed == null
          ? null
          : (List<DailyThought>.of(seed)..sort((a, b) => a.id.compareTo(b.id)));

  static const String assetPath = 'assets/pensees/pensees_100_site.json';

  /// Date de référence de la rotation = 1re `publish_date` du pack.
  static final DateTime referenceDate = DateTime(2026, 9, 4);

  final AssetBundle? _bundle;
  final List<DailyThought>? _seed;
  List<DailyThought>? _cache;

  Future<List<DailyThought>> load() async {
    if (_seed != null) return _seed;
    if (_cache != null) return _cache!;
    final raw = await (_bundle ?? rootBundle).loadString(assetPath);
    final list =
        (jsonDecode(raw) as List)
            .cast<Map<String, dynamic>>()
            .map(DailyThought.fromJson)
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    _cache = list;
    return list;
  }

  Future<int> count() async => (await load()).length;

  /// Pensée du jour pour [now] (heure LOCALE de l'appareil — les utilisateurs FR
  /// sont sur Europe/Paris ; la rotation bascule à minuit local).
  ///
  /// - Période du pack (une `publish_date` correspond au jour) → l'entrée EXACTE.
  /// - Avant / après la période → rotation cyclique DÉTERMINISTE sur les 100
  ///   entrées : `((jours depuis referenceDate) mod 100)`. Jamais de résultat
  ///   nul, jamais d'écran vide.
  Future<DailyThought> thoughtFor(DateTime now) async {
    final all = await load();
    final today = DateTime(now.year, now.month, now.day);

    for (final t in all) {
      final p = t.publishDate;
      if (p.year == today.year &&
          p.month == today.month &&
          p.day == today.day) {
        return t;
      }
    }

    final days = today.difference(referenceDate).inDays;
    final n = all.length;
    final idx = ((days % n) + n) % n; // robuste aux valeurs négatives
    return all[idx];
  }

  Future<DailyThought> today() => thoughtFor(DateTime.now());
}
