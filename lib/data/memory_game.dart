import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'tarot_deck.dart';

/// Niveaux du Jeu Auryel (jeu de paires).
///
/// [apiDifficulty] mappe l'enum sur les chaînes du backend (easy/medium/hard).
/// [rewardThresholdSeconds] est la VALEUR D'AFFICHAGE du seuil de jeu
/// (« réussir en moins de N s ») — la décision réelle (et le montant
/// d'Étoiles, désormais IDENTIQUE pour les 3 niveaux — GROS CHANTIER AURYEL
/// Prompt 3/5, règle `mini_game_completed`) est prise UNIQUEMENT par le
/// serveur.
enum GameDifficulty {
  facile(
    cardCount: 8,
    label: 'Facile',
    apiDifficulty: 'easy',
    rewardThresholdSeconds: 20,
  ),
  moyen(
    cardCount: 12,
    label: 'Moyen',
    apiDifficulty: 'medium',
    rewardThresholdSeconds: 40,
  ),
  intense(
    cardCount: 16,
    label: 'Difficile',
    apiDifficulty: 'hard',
    rewardThresholdSeconds: 80,
  );

  const GameDifficulty({
    required this.cardCount,
    required this.label,
    required this.apiDifficulty,
    required this.rewardThresholdSeconds,
  });

  final int cardCount;
  final String label;
  final String apiDifficulty;
  final int rewardThresholdSeconds;

  int get pairCount => cardCount ~/ 2;

  static GameDifficulty? fromApi(String value) {
    for (final d in GameDifficulty.values) {
      if (d.apiDifficulty == value) return d;
    }
    return null;
  }
}

/// Une carte du plateau. `pairKey` identifie la paire ; `faceAsset` est
/// l'illustration face visible (réutilise les arcanes du Tirage).
@immutable
class MemoryCard {
  const MemoryCard({
    required this.slotId,
    required this.pairKey,
    required this.faceAsset,
    this.revealed = false,
    this.matched = false,
  });

  /// Position stable dans la grille (0..cardCount-1) — sert de clé de widget.
  final int slotId;
  final String pairKey;
  final String faceAsset;
  final bool revealed;
  final bool matched;

  MemoryCard copyWith({bool? revealed, bool? matched}) => MemoryCard(
    slotId: slotId,
    pairKey: pairKey,
    faceAsset: faceAsset,
    revealed: revealed ?? this.revealed,
    matched: matched ?? this.matched,
  );
}

/// Contrôleur d'une partie de Memory. Toute la règle du jeu est ici (aucune
/// logique dans `build()`). Testable : `Random` injectable pour un mélange
/// déterministe, et [resolveDelay] réglable (0 en test).
///
/// IMPORTANT : ce contrôleur ne crédite AUCUN temps de consultation, AUCUNE
/// récompense. Il n'expose que des statistiques ludiques locales.
class MemoryGame extends ChangeNotifier {
  MemoryGame({
    Random? random,
    this.resolveDelay = const Duration(milliseconds: 700),
    DateTime Function()? clock,
  }) : _random = random ?? Random(),
       _clock = clock ?? DateTime.now;

  final Random _random;
  final Duration resolveDelay;
  final DateTime Function() _clock;

  /// Dos de carte commun (asset Auryel existant).
  static const String backAsset = 'assets/images/tarot_card_back.png';

  GameDifficulty _difficulty = GameDifficulty.facile;
  List<MemoryCard> _cards = const [];
  int _moves = 0;
  int _matchedPairs = 0;
  bool _resolving = false;
  bool _started = false;
  bool _won = false;
  DateTime? _startedAt;
  DateTime? _endedAt;
  Timer? _resolveTimer;
  final List<int> _flipped = []; // slotIds en attente de comparaison

  GameDifficulty get difficulty => _difficulty;
  List<MemoryCard> get cards => List.unmodifiable(_cards);
  int get moves => _moves;
  int get matchedPairs => _matchedPairs;
  int get totalPairs => _difficulty.pairCount;
  bool get isResolving => _resolving;
  bool get hasStarted => _started;
  bool get isWon => _won;

  /// Temps de jeu (fige à la victoire).
  Duration get elapsed {
    final start = _startedAt;
    if (start == null) return Duration.zero;
    final end = _endedAt ?? _clock();
    return end.difference(start);
  }

  /// Démarre une nouvelle partie au niveau [difficulty].
  void start(GameDifficulty difficulty) {
    _resolveTimer?.cancel();
    _resolveTimer = null;
    _difficulty = difficulty;
    _moves = 0;
    _matchedPairs = 0;
    _resolving = false;
    _won = false;
    _flipped.clear();
    _endedAt = null;
    _startedAt = _clock();
    _started = true;
    _cards = _buildDeck(difficulty);
    notifyListeners();
  }

  List<MemoryCard> _buildDeck(GameDifficulty difficulty) {
    // Sélection déterministe-par-mélange des arcanes servant de faces.
    final pool = [...kTarotMajorArcana];
    pool.shuffle(_random);
    final faces = pool.take(difficulty.pairCount).toList();

    final deck = <MemoryCard>[];
    for (final arcana in faces) {
      deck.add(
        MemoryCard(
          slotId: -1,
          pairKey: arcana.key,
          faceAsset: arcana.assetPath,
        ),
      );
      deck.add(
        MemoryCard(
          slotId: -1,
          pairKey: arcana.key,
          faceAsset: arcana.assetPath,
        ),
      );
    }
    deck.shuffle(_random);
    return [
      for (var i = 0; i < deck.length; i++)
        MemoryCard(
          slotId: i,
          pairKey: deck[i].pairKey,
          faceAsset: deck[i].faceAsset,
        ),
    ];
  }

  int _indexOfSlot(int slotId) => _cards.indexWhere((c) => c.slotId == slotId);

  /// Retourne la carte [slotId]. Ignore : partie finie, résolution en cours,
  /// carte déjà retournée, carte déjà trouvée, 3ᵉ carte.
  void flip(int slotId) {
    if (!_started || _won || _resolving) return;
    final i = _indexOfSlot(slotId);
    if (i < 0) return;
    final card = _cards[i];
    if (card.revealed || card.matched) return;
    if (_flipped.contains(slotId)) return;
    if (_flipped.length >= 2) return;

    _cards[i] = card.copyWith(revealed: true);
    _flipped.add(slotId);

    if (_flipped.length == 2) {
      _moves++;
      final a = _cards[_indexOfSlot(_flipped[0])];
      final b = _cards[_indexOfSlot(_flipped[1])];
      if (a.pairKey == b.pairKey) {
        _markMatched(a.slotId, b.slotId);
      } else {
        _scheduleFlipBack();
      }
    }
    notifyListeners();
  }

  void _markMatched(int slotA, int slotB) {
    for (final s in [slotA, slotB]) {
      final i = _indexOfSlot(s);
      _cards[i] = _cards[i].copyWith(matched: true, revealed: true);
    }
    _matchedPairs++;
    _flipped.clear();
    if (_matchedPairs == _difficulty.pairCount) {
      _won = true;
      _endedAt = _clock();
    }
  }

  void _scheduleFlipBack() {
    _resolving = true;
    if (resolveDelay <= Duration.zero) {
      _flipBackNow();
    } else {
      _resolveTimer = Timer(resolveDelay, _flipBackNow);
    }
  }

  void _flipBackNow() {
    _resolveTimer = null;
    for (final s in _flipped) {
      final i = _indexOfSlot(s);
      if (i >= 0 && !_cards[i].matched) {
        _cards[i] = _cards[i].copyWith(revealed: false);
      }
    }
    _flipped.clear();
    _resolving = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _resolveTimer?.cancel();
    _resolveTimer = null;
    super.dispose();
  }
}
