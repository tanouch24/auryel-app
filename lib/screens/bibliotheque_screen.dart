import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../api/api_client.dart';
import '../data/tarot_deck.dart';
import '../data/tirage.dart';
import '../state/auth_controller.dart';
import '../theme/auryel_theme.dart';
import 'onboarding/email_auth_screen.dart';

/// Onglet « Bibliothèque » — section « Mon parcours » : l'historique des
/// tirages sauvegardés, alimenté par `GET /api/tirages` (newest-first,
/// pagination par curseur `before`). Toutes les données affichées viennent du
/// serveur ; le deck local ne sert qu'au mapping `key -> assetPath`.
class BibliothequeScreen extends StatefulWidget {
  const BibliothequeScreen({super.key, this.showBackButton = false});

  /// B10.1 — `true` quand l'écran est ouvert en secondaire depuis « Mon
  /// espace » (« Voir mes tirages ») : on affiche alors une flèche retour en
  /// haut à gauche. `false` (défaut) quand il est monté comme onglet de la
  /// bottom nav — aucune flèche, le comportement onglet ne change pas.
  final bool showBackButton;

  @override
  State<BibliothequeScreen> createState() => _BibliothequeScreenState();
}

enum _LoadState {
  loading,
  loaded,
  empty,
  retryable,
  requiresAuthentication,
  fatal,
}

class _BibliothequeScreenState extends State<BibliothequeScreen> {
  _LoadState _state = _LoadState.loading;
  final List<TirageResult> _tirages = [];
  String? _nextCursor;
  bool _loadingMore = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final auth = AuthScope.maybeOf(context);
    if (auth == null) {
      setState(() => _state = _LoadState.requiresAuthentication);
      return;
    }
    setState(() {
      _state = _LoadState.loading;
      _tirages.clear();
      _nextCursor = null;
    });
    final token = await auth.currentToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      setState(() => _state = _LoadState.requiresAuthentication);
      return;
    }
    try {
      final resp = await auth.tirageApi.list(bearer: token, limit: 20);
      if (!mounted) return;
      setState(() {
        _tirages
          ..clear()
          ..addAll(resp.tirages);
        _nextCursor = resp.nextCursor;
        _state = _tirages.isEmpty ? _LoadState.empty : _LoadState.loaded;
      });
    } on ApiUnauthorizedException {
      await auth.invalidateSession();
      if (!mounted) return;
      setState(() => _state = _LoadState.requiresAuthentication);
    } on ApiNetworkException {
      if (!mounted) return;
      setState(() => _state = _LoadState.retryable);
    } on ApiException {
      if (!mounted) return;
      setState(() => _state = _LoadState.fatal);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextCursor == null) return;
    final auth = AuthScope.maybeOf(context);
    if (auth == null) return;
    setState(() => _loadingMore = true);
    final token = await auth.currentToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      setState(() {
        _loadingMore = false;
        _state = _LoadState.requiresAuthentication;
      });
      return;
    }
    try {
      final resp = await auth.tirageApi.list(
        bearer: token,
        limit: 20,
        before: _nextCursor,
      );
      if (!mounted) return;
      setState(() {
        _tirages.addAll(resp.tirages);
        _nextCursor = resp.nextCursor;
        _loadingMore = false;
      });
    } on ApiUnauthorizedException {
      await auth.invalidateSession();
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _state = _LoadState.requiresAuthentication;
      });
    } on ApiNetworkException {
      if (!mounted) return;
      setState(
        () => _loadingMore = false,
      ); // le bouton reste, on peut réessayer
    } on ApiException {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _goToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadInitial,
            color: AuryelColors.goldLight,
            backgroundColor: AuryelColors.surface,
            child: _body(),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final header = <Widget>[
      if (widget.showBackButton) ...[
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Retour',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const PhosphorIcon(
              PhosphorIconsRegular.arrowLeft,
              size: 20,
              color: AuryelColors.textMuted,
            ),
          ),
        ),
        const SizedBox(height: 4),
      ] else
        const SizedBox(height: 24),
      Text(
        'Bibliothèque',
        style: AuryelText.display(fontSize: 26, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Text(
        'Mon parcours',
        style: AuryelText.body(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AuryelColors.goldLight,
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 18),
    ];

    switch (_state) {
      case _LoadState.loading:
        return _scroll([
          ...header,
          const Padding(
            padding: EdgeInsets.only(top: 60),
            child: Center(
              child: CircularProgressIndicator(color: AuryelColors.goldLight),
            ),
          ),
        ]);
      case _LoadState.empty:
        return _scroll([
          ...header,
          _centerText('Tes tirages apparaîtront ici.'),
        ]);
      case _LoadState.requiresAuthentication:
        return _scroll([
          ...header,
          _centerText('Reconnecte-toi pour retrouver ton parcours.'),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _goToLogin,
              child: Text(
                'Se reconnecter',
                style: AuryelText.body(
                  color: AuryelColors.goldLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ]);
      case _LoadState.retryable:
        return _scroll([
          ...header,
          _centerText('Impossible de charger ton parcours pour le moment.'),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _loadInitial,
              child: Text(
                'Réessayer',
                style: AuryelText.body(
                  color: AuryelColors.goldLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ]);
      case _LoadState.fatal:
        return _scroll([
          ...header,
          _centerText('Une erreur est survenue. Réessaie plus tard.'),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _loadInitial,
              child: Text(
                'Actualiser',
                style: AuryelText.body(
                  color: AuryelColors.goldLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ]);
      case _LoadState.loaded:
        return _scroll([
          ...header,
          for (final t in _tirages) ...[
            _TirageCard(tirage: t),
            const SizedBox(height: 16),
          ],
          if (_nextCursor != null)
            Center(
              child: TextButton(
                onPressed: _loadingMore ? null : _loadMore,
                child: Text(
                  _loadingMore ? 'Chargement…' : 'Afficher plus',
                  style: AuryelText.body(
                    color: _loadingMore
                        ? AuryelColors.textMuted
                        : AuryelColors.goldLight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
        ]);
    }
  }

  Widget _scroll(List<Widget> children) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    children: children,
  );

  Widget _centerText(String text) => Padding(
    padding: const EdgeInsets.only(top: 60),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AuryelText.body(fontSize: 13, color: AuryelColors.textMuted),
      ),
    ),
  );
}

/// Une entrée « Mon parcours ».
class _TirageCard extends StatelessWidget {
  const _TirageCard({required this.tirage});

  final TirageResult tirage;

  static const _mois = [
    'janv.',
    'févr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sept.',
    'oct.',
    'nov.',
    'déc.',
  ];

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    final mm = (local.month >= 1 && local.month <= 12)
        ? _mois[local.month - 1]
        : '${local.month}';
    return '${local.day} $mm ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final names = tirage.cards.isNotEmpty
        ? tirage.cards.map((c) => c.name).toList()
        : tirage.cardKeys;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AuryelColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AuryelColors.warmBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _formatDate(tirage.createdAt),
                style: AuryelText.body(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.textMuted,
                  letterSpacing: 0.6,
                ),
              ),
              if (tirage.advisorId != null &&
                  tirage.advisorId!.trim().isNotEmpty) ...[
                const Spacer(),
                Text(
                  'Avec ${tirage.advisorId}',
                  style: AuryelText.body(
                    fontSize: 11.5,
                    color: AuryelColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < tirage.cardKeys.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    right: i == tirage.cardKeys.length - 1 ? 0 : 8,
                  ),
                  child: _MiniThumb(
                    assetPath: tarotArcanaByKey(tirage.cardKeys[i])?.assetPath,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            names.join(' · '),
            style: AuryelText.display(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tirage.combinedInterpretation,
            style: AuryelText.body(
              fontSize: 12.5,
              height: 1.55,
              color: AuryelColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniThumb extends StatelessWidget {
  const _MiniThumb({required this.assetPath});

  final String? assetPath;

  static const double _w = 42;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _w,
      height: _w * 379 / 215,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AuryelColors.gold.withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      child: assetPath != null
          ? Image.asset(assetPath!, fit: BoxFit.cover)
          : Container(
              color: AuryelColors.surfaceLight,
              alignment: Alignment.center,
              child: Transform.rotate(
                angle: 0.785398,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: AuryelColors.goldGradient,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
    );
  }
}
