import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../api/api_client.dart';
import '../data/daily_like_store.dart';
import '../data/daily_mission_tracker.dart';
import '../data/tarot_deck.dart';
import '../data/tirage.dart';
import '../screens/chat_screen.dart';
import '../screens/onboarding/email_auth_screen.dart';
import '../state/auryel_state.dart';
import '../state/auth_controller.dart';
import '../state/consultation_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/advisors_carousel.dart';
import '../widgets/gold_button.dart';
import '../widgets/tarot_card_back.dart';
import '../widgets/tarot_fan.dart';

/// Onglet « Tirage » — l'utilisateur choisit LUI-MÊME 3 cartes parmi les 22
/// arcanes majeurs, mélangés une fois à l'ouverture. Aucune carte n'est servie
/// d'office, l'ordre des taps est conservé.
///
/// TIRAGE T3 : « Révéler mon tirage » **sauvegarde d'abord le tirage côté
/// backend** (`POST /api/tirages`, aucun crédit, aucun LLM). Ce n'est qu'après
/// un 201 que les cartes se retournent, avec les noms / interprétations /
/// lecture d'ensemble **RENDUS PAR LE SERVEUR** ([TirageResult]). Le deck local
/// ne sert plus qu'au choix visuel et au mapping `key -> assetPath`.
class TirageScreen extends StatefulWidget {
  const TirageScreen({super.key});

  @override
  State<TirageScreen> createState() => _TirageScreenState();
}

/// États du bouton / bandeau de sauvegarde.
enum _SaveState { idle, saving, saved, saveRetryable, requiresAuthentication }

class _TirageScreenState extends State<TirageScreen> {
  final Random _random = Random();

  /// Copie mélangée UNE fois (ouverture de l'écran, ou « Recommencer »).
  late List<TarotArcana> _deck;

  /// Index (dans [_deck]) des cartes touchées, dans l'ordre exact des taps.
  final List<int> _selectedIndexes = [];

  bool _revealed = false;
  _SaveState _save = _SaveState.idle;

  /// Tirage canonique renvoyé par le serveur (source de vérité de l'affichage).
  TirageResult? _result;

  /// Panneau de lecture (phase révélée) — indice de scroll « Voir la suite ».
  final ScrollController _revealScroll = ScrollController();
  bool _revealScrollable = false;
  bool _revealAtBottom = false;

  static const int _maxCards = 3;

  @override
  void dispose() {
    _revealScroll.dispose();
    super.dispose();
  }

  void _onRevealScrollMetrics() {
    if (!_revealScroll.hasClients) return;
    final p = _revealScroll.position;
    final scrollable = p.maxScrollExtent > 8;
    final atBottom = p.pixels >= p.maxScrollExtent - 24;
    if (scrollable != _revealScrollable || atBottom != _revealAtBottom) {
      setState(() {
        _revealScrollable = scrollable;
        _revealAtBottom = atBottom;
      });
    }
  }

  /// Ordre du deck mélangé (slugs) — pour les tests uniquement.
  @visibleForTesting
  List<String> get debugDeckKeys => _deck.map((c) => c.key).toList();

  /// Slugs sélectionnés, dans l'ordre exact des taps — pour les tests uniquement.
  @visibleForTesting
  List<String> get debugSelectionKeys =>
      _selectedIndexes.map((i) => _deck[i].key).toList();

  @override
  void initState() {
    super.initState();
    _deck = List.of(kTarotMajorArcana)..shuffle(_random);
  }

  void _select(int deckIndex) {
    if (_revealed || _save == _SaveState.saving) return;
    if (_selectedIndexes.contains(deckIndex)) return;
    if (_selectedIndexes.length >= _maxCards) return;
    setState(() => _selectedIndexes.add(deckIndex));
  }

  List<String> get _selectedKeys =>
      _selectedIndexes.map((i) => _deck[i].key).toList(growable: false);

  /// « Révéler mon tirage » : sauvegarde backend PUIS révélation.
  Future<void> _saveAndReveal() async {
    if (_revealed ||
        _save == _SaveState.saving ||
        _selectedIndexes.length != _maxCards) {
      return;
    }
    final auth = AuthScope.of(context); // capturé avant tout await
    setState(() => _save = _SaveState.saving);

    final token = await auth.currentToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      setState(() => _save = _SaveState.requiresAuthentication);
      return;
    }

    try {
      final result = await auth.tirageApi.create(
        bearer: token,
        cardKeys: _selectedKeys,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _revealed = true;
        _save = _SaveState.saved;
      });
      // Mission du jour « Fais ton tirage » : cochée sur une SAUVEGARDE réelle
      // (pas la simple ouverture de l'onglet). Aucune récompense.
      DailyMissionTracker().markDone(DailyMissionTracker.tirage);
      // Une fois le panneau de lecture posé : savoir s'il déborde (indice
      // « Voir la suite »).
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _onRevealScrollMetrics(),
      );
    } on ApiUnauthorizedException {
      await auth.invalidateSession();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
        (route) => false,
      );
    } on ApiNetworkException {
      if (!mounted) return;
      setState(() => _save = _SaveState.saveRetryable);
    } on ApiException {
      // 5xx / réponse inattendue — récupérable, les 3 sélections restent.
      if (!mounted) return;
      setState(() => _save = _SaveState.saveRetryable);
    }
  }

  void _restart() {
    setState(() {
      _deck = List.of(kTarotMajorArcana)..shuffle(_random);
      _selectedIndexes.clear();
      _result = null;
      _revealed = false;
      _save = _SaveState.idle;
    });
  }

  String get _subtitle {
    switch (_selectedIndexes.length) {
      case 0:
        return 'Choisis trois cartes.';
      case 1:
        return 'Encore deux cartes…';
      case 2:
        return 'Encore une carte…';
      default:
        return 'Ton tirage est prêt.';
    }
  }

  /// Chemins des faces (ordre serveur = ordre de sélection), ou `null` avant
  /// révélation.
  List<String?> get _slotFaces {
    if (!_revealed || _result == null) {
      return const [null, null, null];
    }
    final cards = _result!.cards.isNotEmpty
        ? _result!.cards.map((c) => c.key).toList()
        : _result!.cardKeys;
    return [
      for (var i = 0; i < 3; i++)
        i < cards.length ? tarotArcanaByKey(cards[i])?.assetPath : null,
    ];
  }

  @override
  Widget build(BuildContext context) {
    // B8.4 — fond = TAPIS VIDE fourni (`tarot_table_blank.png`), 3 emplacements
    // centraux libres. UNE seule représentation des cartes choisies : la carte
    // dos (`tarot_card_back.png`) posée sur l'emplacement, qui se retourne sur
    // place à la révélation. Aucun récap, aucune 2e rangée d'images.
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/tarot_table_blank.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xE6120E17),
                      Color(0x73120E17),
                      Color(0x8C120E17),
                      Color(0xF2120E17),
                    ],
                    stops: [0.0, 0.34, 0.66, 1.0],
                  ),
                ),
              ),
            ),
            // LA représentation unique des cartes choisies (dos -> face sur
            // place). En dessous du contenu : la lecture, en phase révélée,
            // occupe un panneau bas qui ne recouvre jamais les cartes.
            Positioned.fill(
              child: IgnorePointer(
                child: _TapisCards(
                  count: _selectedIndexes.length,
                  revealed: _revealed,
                  faces: _slotFaces,
                ),
              ),
            ),
            SafeArea(
              child: _revealed
                  ? _buildReveal(context)
                  : _buildSelection(context),
            ),
            // Cœur « j'aime » local du tirage (inchangé).
            const Positioned(
              top: 4,
              right: 6,
              child: SafeArea(child: _TirageLikeButton()),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Phase 1 — choix des 3 cartes (face cachée) + sauvegarde
  // ---------------------------------------------------------------------------

  Widget _buildSelection(BuildContext context) {
    final count = _selectedIndexes.length;
    return Column(
      children: [
        const SizedBox(height: 24),
        Text(
          'Ton tirage',
          style: AuryelText.display(fontSize: 26, fontWeight: FontWeight.w600),
        ).animate().fadeIn(duration: 500.ms),
        const SizedBox(height: 8),
        Text(
          _subtitle,
          style: AuryelText.body(fontSize: 13, color: AuryelColors.textMuted),
        ),
        const SizedBox(height: 6),
        Text(
          '$count / $_maxCards',
          style: AuryelText.body(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AuryelColors.goldLight,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        // Éventail des 22 arcanes en haut (inchangé). Les cartes choisies se
        // POSENT sur les emplacements du tapis (overlay `_TapisCards`) — pas de
        // récap ailleurs.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                heightFactor: 0.62,
                child: Opacity(
                  opacity: count == _maxCards ? 0.72 : 1,
                  child: TarotFan(
                    count: _deck.length,
                    selectionNumberFor: _selectionNumber,
                    onTap: _select,
                    enabled:
                        !_revealed &&
                        _save != _SaveState.saving &&
                        count < _maxCards,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (count == _maxCards) _buildSaveArea(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSaveArea() {
    final saving = _save == _SaveState.saving;
    final retry = _save == _SaveState.saveRetryable;
    final needsAuth = _save == _SaveState.requiresAuthentication;

    String? message;
    if (saving) {
      message = 'Enregistrement de ton tirage…';
    } else if (retry) {
      message = "Impossible d'enregistrer ton tirage pour le moment.";
    } else if (needsAuth) {
      message = 'Reconnecte-toi pour enregistrer ton tirage.';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 8),
      child: Column(
        children: [
          if (message != null) ...[
            Text(
              message,
              textAlign: TextAlign.center,
              style: AuryelText.body(
                fontSize: 12.5,
                color: saving ? AuryelColors.textMuted : AuryelColors.goldLight,
              ),
            ),
            const SizedBox(height: 10),
          ],
          AuryelGoldButton(
            label: saving
                ? 'Enregistrement…'
                : (retry ? 'Réessayer' : 'Révéler mon tirage'),
            enabled: !saving,
            onTap: _saveAndReveal,
          ).animate().fadeIn(duration: 300.ms),
        ],
      ),
    );
  }

  /// Rang (1..3) de la carte [deckIndex] dans la sélection, ou `null`.
  int? _selectionNumber(int deckIndex) {
    final pos = _selectedIndexes.indexOf(deckIndex);
    return pos == -1 ? null : pos + 1;
  }

  // ---------------------------------------------------------------------------
  // Phase 2 — révélation (données SERVEUR) + lecture + CTA
  // ---------------------------------------------------------------------------

  /// Confirmation avant d'entrer dans le chat depuis un tirage.
  ///
  /// - Wording adapté si une consultation avec CE conseiller est DÉJÀ active
  ///   (« Continuer » plutôt que « Démarrer »).
  /// - « Annuler » : ferme seulement la popup, rien d'autre.
  /// - « Commencer » / « Continuer » : SIMPLE `Navigator.push(ChatScreen(...))`.
  ///   Aucun `POST /api/consultation/message`, aucune ouverture de session,
  ///   aucun crédit — le crédit reste consommé au premier message utilisateur.
  Future<void> _confirmAndOpenChat(
    BuildContext context,
    AdvisorInfo advisor,
    String tirageId,
  ) async {
    final consultation = ConsultationScope.maybeReadOf(context);
    final sameAdvisorActive =
        consultation != null &&
        consultation.hasActiveSession &&
        consultation.active?.advisorId == advisor.guideKey;
    // Capturé AVANT l'await : aucun usage de `context` après la frontière async.
    final navigator = Navigator.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AuryelColors.surface,
        title: Text(
          sameAdvisorActive
              ? 'Continuer avec ${advisor.name} ?'
              : 'Démarrer une consultation avec ${advisor.name} ?',
          style: AuryelText.display(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Text(
          sameAdvisorActive
              ? 'Ton tirage sera ajouté à ta conversation en cours avec '
                    '${advisor.name}.'
              : 'Ton tirage sera transmis à ${advisor.name} pour pouvoir en '
                    'parler avec toi.\n\nLa consultation démarrera lorsque tu '
                    'enverras ton premier message.',
          style: AuryelText.body(
            fontSize: 13.5,
            height: 1.5,
            color: AuryelColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Annuler',
              style: AuryelText.body(color: AuryelColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              sameAdvisorActive ? 'Continuer' : 'Commencer',
              style: AuryelText.body(
                color: AuryelColors.goldLight,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    navigator.push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(advisor: advisor, tirageId: tirageId),
      ),
    );
  }

  Widget _buildReveal(BuildContext context) {
    final result = _result!;
    final advisor = advisorByNameOrNull(
      AuryelStateScope.of(context).selectedAdvisor,
    );
    // Ordre = celui renvoyé par le serveur (= ordre de sélection).
    final cards = result.cards.isNotEmpty
        ? result.cards
        : [
            for (final k in result.cardKeys)
              TirageCardDto(key: k, name: k, interpretation: ''),
          ];

    // B8.4 §17-18 — AUCUNE nouvelle rangée d'images : ce sont les 3 cartes
    // POSÉES SUR LE TAPIS (overlay `_TapisCards`) qui se retournent. Ici, sous
    // les cartes, uniquement la LECTURE, dans un panneau bas scrollable.
    return Column(
      children: [
        const SizedBox(height: 10),
        Text(
          'Ton tirage est prêt.',
          style: AuryelText.body(fontSize: 13, color: AuryelColors.textMuted),
        ),
        // TIRAGE-UX §6 — les 3 cartes (overlay `_TapisCards`, `_cy` remonté)
        // deviennent le centre visuel : moins d'espace mort au-dessus, plus de
        // place pour la lecture en dessous.
        const Spacer(flex: 42),
        Expanded(
          flex: 58,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00120E17), Color(0xF2120E17)],
                stops: [0.0, 0.14],
              ),
            ),
            child: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    _onRevealScrollMetrics();
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _revealScroll,
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < cards.length; i++) ...[
                          _CardDetail(index: i, card: cards[i]),
                          const SizedBox(height: 18),
                        ],
                        const SizedBox(height: 4),
                        Divider(color: AuryelColors.warmBorder, height: 1),
                        const SizedBox(height: 18),
                        Text(
                          'Lecture de ton tirage',
                          style: AuryelText.display(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          result.combinedInterpretation,
                          style: AuryelText.body(
                            fontSize: 13.5,
                            height: 1.6,
                            color: AuryelColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (advisor != null)
                          AuryelGoldButton(
                            label: 'En parler avec ${advisor.name}',
                            onTap: () => _confirmAndOpenChat(
                              context,
                              advisor,
                              result.tirageId,
                            ),
                          ),
                        const SizedBox(height: 12),
                        Center(
                          child: TextButton(
                            onPressed: _restart,
                            child: Text(
                              'Recommencer le tirage',
                              style: AuryelText.body(
                                fontSize: 12.5,
                                color: AuryelColors.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // TIRAGE-UX §7 — indice de scroll : chevron + « Voir la suite »,
                // léger va-et-vient vertical, RETIRÉ de l'arbre une fois le bas
                // atteint (ou si le contenu tient déjà à l'écran) — donc aucune
                // animation résiduelle.
                if (_revealScrollable && !_revealAtBottom)
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 6,
                    child: IgnorePointer(child: _ScrollHint()),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Indice « il y a une suite » : chevron bas + libellé court. Petit va-et-vient
/// vertical FINI (quelques allers-retours puis repos) — jamais d'animation
/// infinie, pour ne pas bloquer `pumpAndSettle`. Le widget est de toute façon
/// retiré de l'arbre dès qu'on a assez scrollé.
class _ScrollHint extends StatelessWidget {
  const _ScrollHint();

  @override
  Widget build(BuildContext context) {
    final chevron =
        const PhosphorIcon(
              PhosphorIconsBold.caretDown,
              size: 13,
              color: AuryelColors.goldLight,
            )
            .animate(onPlay: (c) => c.repeat(reverse: true, count: 6))
            .moveY(
              begin: -2,
              end: 3,
              duration: 650.ms,
              curve: Curves.easeInOut,
            );

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AuryelColors.backgroundDeep.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AuryelColors.gold.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Voir la suite',
              style: AuryelText.body(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AuryelColors.goldLight,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 6),
            chevron,
          ],
        ),
      ),
    );
  }
}

/// B8.4 §12-18 — LA représentation unique des cartes choisies : jusqu'à 3
/// cartes DOS (`tarot_card_back.png`) posées sur les 3 emplacements CENTRAUX du
/// tapis vide, qui se retournent SUR PLACE (même position, même taille) à la
/// révélation. Overlay `IgnorePointer` : les taps passent vers l'éventail / les
/// boutons.
class _TapisCards extends StatelessWidget {
  const _TapisCards({
    required this.count,
    required this.revealed,
    required this.faces,
  });

  final int count;
  final bool revealed;
  final List<String?> faces;

  // Emplacements des 3 cartes sur le TAPIS VIDE (fractions d'écran), calibrés
  // sur tarot_table_blank.png. En SÉLECTION : sous l'éventail (`_cySelect`).
  // APRÈS RÉVÉLATION (`_cyReveal`) : nettement remontées — les cartes
  // deviennent le centre visuel, moins d'espace mort au-dessus (TIRAGE-UX §6).
  static const List<double> _cx = [0.255, 0.500, 0.745];
  static const double _cySelect = 0.545;
  static const double _cyReveal = 0.40;
  static const double _cardHFrac = 0.165; // hauteur carte / hauteur écran
  static const double _ratio = 781 / 1312; // w/h de tarot_card_back.png

  double get _cy => revealed ? _cyReveal : _cySelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        final cardH = h * _cardHFrac;
        final cardW = cardH * _ratio;
        // Le groupe de cartes glisse doucement vers le haut à la révélation
        // (mêmes positions X, même taille — seule la hauteur du groupe change).
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: _cy),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, cy, _) => Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < 3; i++)
                if (revealed || i < count)
                  Positioned(
                    left: w * _cx[i] - cardW / 2,
                    top: h * cy - cardH / 2,
                    width: cardW,
                    height: cardH,
                    child: _Slot(
                      index: i,
                      revealed: revealed,
                      facePath: faces.length > i ? faces[i] : null,
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.index,
    required this.revealed,
    required this.facePath,
  });

  final int index;
  final bool revealed;
  final String? facePath;

  @override
  Widget build(BuildContext context) {
    final showFace = revealed && facePath != null;
    final Widget child = showFace
        ? ClipRRect(
            key: ValueKey('tarot-reveal-$index'),
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(facePath!, fit: BoxFit.contain),
          )
        : Stack(
            key: const ValueKey('back'),
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              const Positioned.fill(child: TarotCardBack(selected: true)),
              Positioned(top: -10, child: _NumberPastille(number: index + 1)),
            ],
          );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (w, anim) {
        // Retournement Y simple.
        final rotate = Tween<double>(begin: 3.1416 / 2, end: 0).animate(anim);
        return AnimatedBuilder(
          animation: rotate,
          child: w,
          builder: (_, ch) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(rotate.value),
            child: Opacity(opacity: anim.value, child: ch),
          ),
        );
      },
      child: child,
    );
  }
}

/// Pastille or numérotée (1/2/3) posée sur le coin d'une carte de l'emplacement.
class _NumberPastille extends StatelessWidget {
  const _NumberPastille({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AuryelColors.goldGradient,
      ),
      child: Text(
        '$number',
        style: AuryelText.body(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AuryelColors.backgroundDeep,
        ),
      ),
    );
  }
}

/// B8.3 §4-D — cœur « j'aime » local du tirage du jour (bucket `tarot`).
class _TirageLikeButton extends StatefulWidget {
  const _TirageLikeButton();

  @override
  State<_TirageLikeButton> createState() => _TirageLikeButtonState();
}

class _TirageLikeButtonState extends State<_TirageLikeButton> {
  final DailyLikeStore _store = DailyLikeStore(bucket: 'tarot');
  bool _liked = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await _store.isLikedToday();
      if (mounted) setState(() => _liked = v);
    } catch (_) {
      /* défaut : non aimé */
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    _busy = true;
    setState(() => _liked = !_liked);
    try {
      final v = await _store.toggleToday();
      if (mounted && v != _liked) setState(() => _liked = v);
    } catch (_) {
      /* garde l'état optimiste */
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: _liked
          ? 'Retirer le tirage des favoris'
          : 'Ajouter le tirage aux favoris',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: PhosphorIcon(
              _liked ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
              size: 20,
              color: _liked ? AuryelColors.goldLight : AuryelColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bloc « Carte N » + nom + interprétation — **texte serveur** ([TirageCardDto]).
class _CardDetail extends StatelessWidget {
  const _CardDetail({required this.index, required this.card});

  final int index;
  final TirageCardDto card;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Carte ${index + 1}',
          style: AuryelText.body(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AuryelColors.textMuted,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          card.name,
          style: AuryelText.display(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          card.interpretation,
          style: AuryelText.body(
            fontSize: 13,
            height: 1.55,
            color: AuryelColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
