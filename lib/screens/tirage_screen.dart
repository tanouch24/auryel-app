import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../api/api_client.dart';
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

  static const int _maxCards = 3;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: _revealed ? _buildReveal(context) : _buildSelection(context),
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
        const SizedBox(height: 16),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < _deck.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        right: i == _deck.length - 1 ? 0 : 10,
                      ),
                      child: _SelectableBack(
                        key: ValueKey('tarot-back-$i'),
                        selectionNumber: _selectionNumber(i),
                        onTap: () => _select(i),
                      ).animate().fadeIn(delay: (18 * i).ms, duration: 350.ms),
                    ),
                ],
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              'Ton tirage',
              style: AuryelText.display(
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Ton tirage est prêt.',
              style: AuryelText.body(
                fontSize: 13,
                color: AuryelColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 22),

          // 3 mini cartes côte à côte, dans l'ordre serveur.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < cards.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    right: i == cards.length - 1 ? 0 : 12,
                  ),
                  child: _MiniCard(
                    key: ValueKey('tarot-reveal-$i'),
                    assetPath: tarotArcanaByKey(cards[i].key)?.assetPath,
                    order: i,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),

          // Détail carte par carte — nom + interprétation SERVEUR.
          for (var i = 0; i < cards.length; i++) ...[
            _CardDetail(index: i, card: cards[i]),
            const SizedBox(height: 18),
          ],

          const SizedBox(height: 6),
          Divider(color: AuryelColors.warmBorder, height: 1),
          const SizedBox(height: 20),

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
          const SizedBox(height: 26),

          if (advisor != null)
            AuryelGoldButton(
              label: 'En parler avec ${advisor.name}',
              // Le clic ouvre une confirmation ; « Commencer » / « Continuer »
              // fait ensuite une SIMPLE navigation vers ChatScreen avec le
              // tirage_id en mémoire. Aucune consultation ouverte, aucun crédit
              // consommé ici — le crédit reste débité au PREMIER message.
              onTap: () =>
                  _confirmAndOpenChat(context, advisor, result.tirageId),
            ),
          const SizedBox(height: 14),
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
    );
  }
}

/// Dos de carte tapable — motif or sur `surfaceLight`. Quand la carte est
/// sélectionnée : bordure or vive, léger soulèvement et pastille numérotée.
class _SelectableBack extends StatelessWidget {
  const _SelectableBack({
    super.key,
    required this.selectionNumber,
    required this.onTap,
  });

  final int? selectionNumber;
  final VoidCallback onTap;

  static const double _w = 66;
  static const double _h = 100;

  @override
  Widget build(BuildContext context) {
    final selected = selectionNumber != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, selected ? -14 : 0, 0),
          width: _w,
          height: _h + 16,
          alignment: Alignment.bottomCenter,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                width: _w,
                height: _h,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AuryelColors.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AuryelColors.gold.withValues(
                      alpha: selected ? 0.95 : 0.5,
                    ),
                    width: selected ? 1.6 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: selected
                          ? AuryelColors.gold.withValues(alpha: 0.28)
                          : AuryelColors.backgroundDeep.withValues(alpha: 0.5),
                      blurRadius: selected ? 16 : 8,
                      spreadRadius: selected ? 1 : 0,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: AuryelColors.gold.withValues(alpha: 0.3),
                      width: 0.6,
                    ),
                  ),
                  child: Center(
                    child: Transform.rotate(
                      angle: 0.785398,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          gradient: AuryelColors.goldGradient,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  top: -10,
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AuryelColors.goldGradient,
                    ),
                    child: Text(
                      '$selectionNumber',
                      style: AuryelText.body(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AuryelColors.backgroundDeep,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mini carte révélée. Image réelle si l'`assetPath` local existe pour la clé
/// serveur, sinon un placeholder visuel contrôlé (jamais de crash).
class _MiniCard extends StatelessWidget {
  const _MiniCard({super.key, required this.assetPath, required this.order});

  final String? assetPath;
  final int order;

  @override
  Widget build(BuildContext context) {
    final delay = (order * 250).ms;
    final Widget face = assetPath != null
        ? Image.asset(assetPath!, width: 88, fit: BoxFit.contain)
        : Container(
            width: 88,
            height: 88 * 379 / 215,
            alignment: Alignment.center,
            color: AuryelColors.surfaceLight,
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  gradient: AuryelColors.goldGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
    return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AuryelColors.gold.withValues(alpha: 0.55),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AuryelColors.gold.withValues(alpha: 0.12),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: face,
        )
        .animate()
        .fadeIn(delay: delay, duration: 350.ms)
        .flip(
          direction: Axis.horizontal,
          begin: -0.5,
          end: 0,
          delay: delay,
          duration: 500.ms,
          curve: Curves.easeOut,
        )
        .scaleXY(
          begin: 0.85,
          end: 1,
          delay: delay,
          duration: 450.ms,
          curve: Curves.easeOutCubic,
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
