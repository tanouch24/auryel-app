import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data/consultation.dart';
import '../state/auth_controller.dart';
import '../state/consultation_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/advisors_carousel.dart';
import 'onboarding/email_auth_screen.dart';
import 'premium_screen.dart';

/// Chat réel connecté à `POST /api/consultation/message` (F3 + F4).
///
/// - À l'ouverture (F4) : si une consultation active existe déjà dans
///   [ConsultationScope], on la reprend directement — en-tête au bon
///   conseiller backend, temps restant visible, AUCUNE confirmation.
/// - Sinon (F3) : le 1er message déclenche la confirmation « consultation de
///   2 h ». Le backend reste seule source de vérité : aucun décompte local.
/// - 200 -> l'état renvoyé (consultation + quota) est aussi poussé dans
///   [ConsultationController] pour le reste de l'app.
/// - 402 -> mur Premium (quota resynchronisé, aucune session fabriquée).
///   401 -> purge session + retour login. Réseau/5xx -> texte conservé +
///   bouton Réessayer, sans dupliquer la bulle.
/// - Reprise d'une session active : l'historique backend est chargé UNE seule
///   fois via `GET /api/consultation/messages` (lecture seule, aucun crédit,
///   aucun POST). Le `consultation_id` renvoyé doit correspondre à la session
///   active, sinon rien n'est injecté. Un échec de ce chargement n'empêche
///   jamais d'écrire : un retry discret est proposé.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.advisor, this.tirageId});

  /// Conseiller choisi (affiché tant que le backend n'a pas renvoyé de
  /// consultation). Ensuite `consultation.advisor_id` prime.
  final AdvisorInfo advisor;

  /// T3 — tirage à rattacher à la consultation. Envoyé avec le PREMIER message
  /// tant qu'il n'a pas obtenu un 200 ; ni le passage ici ni le clic du CTA
  /// « En parler avec … » n'ouvrent une consultation ou ne consomment de crédit.
  final String? tirageId;

  /// Exposé pour les tests : formatage de `seconds_remaining`.
  static String debugFormatRemaining(int seconds) =>
      _ChatScreenState.formatRemaining(seconds);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatMessage {
  const _ChatMessage({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  final List<_ChatMessage> _messages = [];
  ConsultationDto? _consultation;

  bool _sending = false;
  bool _firstMessageConfirmed = false;

  /// Message en cours d'envoi / en échec — renvoyé tel quel, jamais dupliqué.
  String? _pending;
  String? _networkError;

  bool _noCredit = false;
  QuotaDto? _noCreditQuota;

  bool _seeded = false;

  /// Chargement de l'historique backend : tenté au plus une fois par ouverture
  /// (le retry remet le drapeau à `false`). `_historyLoading` / `_historyError`
  /// ne pilotent qu'un bandeau discret — jamais le blocage de la saisie.
  AuthController? _auth;
  bool _historyRequested = false;
  bool _historyLoading = false;
  bool _historyError = false;

  /// Exposé pour les tests.
  @visibleForTesting
  bool get debugHistoryError => _historyError;

  /// T3 — tirage rattaché au PREMIER message. Effacé après le premier 200 (les
  /// messages suivants n'envoient plus `tirage_id`) ; CONSERVÉ sur réseau /
  /// timeout / 5xx / 402 pour que le retry garde le contexte.
  String? _pendingTirageId;

  /// Exposé pour les tests.
  @visibleForTesting
  String? get debugPendingTirageId => _pendingTirageId;

  @override
  void initState() {
    super.initState();
    _pendingTirageId = widget.tirageId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    // F4 / TIMER-D.1 — reprise d'une consultation LOGIQUE déjà ouverte : on
    // part du state partagé, pas d'un écran vierge. `hasResumableConsultation`
    // (et non `hasActiveSession`) : l'historique reste visible même hors
    // fenêtre de 5 min et même si le portefeuille de temps est bas. Lecture
    // seule, aucun POST.
    final controller = ConsultationScope.maybeReadOf(context);
    if (controller != null && controller.hasResumableConsultation) {
      _consultation = controller.active;
      _firstMessageConfirmed = true; // consultation existante -> pas de confirmation
      _auth = AuthScope.maybeOf(context);
      _loadHistory();
    }
  }

  /// Charge l'historique de la consultation active. Lecture seule : aucun
  /// crédit, aucun POST. N'injecte les messages QUE si le `consultation_id`
  /// renvoyé correspond à la session active. Idempotent tant que
  /// `_historyRequested` est vrai (protège contre un `didChangeDependencies`
  /// rappelé).
  Future<void> _loadHistory() async {
    if (_historyRequested) return;
    final auth = _auth;
    final activeId = _consultation?.id;
    if (auth == null || activeId == null || activeId.isEmpty) return;

    _historyRequested = true;
    setState(() {
      _historyLoading = true;
      _historyError = false;
    });

    try {
      final token = await auth.currentToken();
      if (!mounted) return;
      if (token == null || token.isEmpty) {
        setState(() => _historyLoading = false);
        return;
      }
      final res = await auth.consultationApi.getMessages(bearer: token);
      if (!mounted) return;

      // consultation_id inattendu -> on n'injecte AUCUN message.
      if (res.consultationId == null || res.consultationId != activeId) {
        setState(() => _historyLoading = false);
        return;
      }

      final restored = <_ChatMessage>[
        for (final m in res.messages)
          if (m.content.trim().isNotEmpty)
            _ChatMessage(fromUser: m.isUser, text: m.content),
      ];
      setState(() {
        _historyLoading = false;
        // Inséré en tête : d'éventuels messages tapés pendant le chargement
        // restent après l'historique, dans l'ordre.
        if (restored.isNotEmpty) _messages.insertAll(0, restored);
      });
      _scrollToEnd();
    } on ApiUnauthorizedException {
      // Un simple chargement d'historique ne casse pas la session : le
      // prochain envoi de message traitera le 401 proprement.
      _failHistory();
    } on ApiNetworkException {
      _failHistory();
    } on ApiException {
      _failHistory();
    } catch (_) {
      _failHistory();
    }
  }

  void _failHistory() {
    if (!mounted) return;
    setState(() {
      _historyLoading = false;
      _historyError = true;
    });
  }

  void _retryHistory() {
    _historyRequested = false;
    _loadHistory();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  AdvisorInfo get _headerAdvisor =>
      advisorByGuideKey(_consultation?.advisorId) ?? widget.advisor;

  bool get _canSend {
    if (_sending || _noCredit) return false;
    return _pending != null || _input.text.trim().isNotEmpty;
  }

  Future<void> _onSendPressed() async {
    if (_sending || _noCredit) return;
    final text = _pending ?? _input.text.trim();
    if (text.isEmpty) return;

    // Capturé avant tout `await` : aucun usage de `context` après une frontière async.
    final auth = AuthScope.of(context);
    final consultation = ConsultationScope.maybeReadOf(context);

    // Confirmation avant le TOUT PREMIER message d'une session.
    if (_consultation == null && !_firstMessageConfirmed) {
      final ok = await _confirmFirstMessage();
      if (ok != true) return; // Annuler -> aucun POST, texte conservé
      _firstMessageConfirmed = true;
    }
    if (!mounted) return;

    if (_pending == null) {
      _pending = text;
      _input.clear();
    }
    setState(() {
      _sending = true;
      _networkError = null;
    });
    _scrollToEnd();

    try {
      final token = await auth.currentToken();
      if (token == null || token.isEmpty) {
        await _goToLogin(auth);
        return;
      }
      final res = await auth.consultationApi.sendMessage(
        bearer: token,
        message: text,
        tirageId: _pendingTirageId,
      );
      if (!mounted) return;
      // F4 — l'état renvoyé alimente aussi le state partagé de l'app.
      consultation?.updateFromMessageResponse(res);
      setState(() {
        _messages.add(_ChatMessage(fromUser: true, text: _pending!));
        _messages.add(_ChatMessage(fromUser: false, text: res.reply));
        _consultation = res.consultation ?? _consultation;
        _pending = null;
        _sending = false;
        // T3 — le tirage a été rattaché : plus jamais renvoyé sur cette session.
        _pendingTirageId = null;
      });
      _scrollToEnd();
    } on ApiUnauthorizedException {
      await _goToLogin(auth);
    } on ApiNoCreditException catch (e) {
      if (!mounted) return;
      // TIMER-D.1 — 402 : cas principal `time_exhausted` (l'ancien `no_credit`
      // reste supporté, même chemin HTTP). On resynchronise `time` + `quota`
      // depuis le corps SANS fabriquer de session.
      final quota = _quotaFrom(e.body);
      final time = ConsultationTimeState.maybeFromJson(e.body['time']);
      consultation?.applyExhausted(time: time, quota: quota);
      setState(() {
        _sending = false;
        _pending = null; // le message N'est PAS parti : pas de bulle
        _noCredit = true;
        _noCreditQuota = quota;
      });
    } on ApiNetworkException {
      _failNetwork('Connexion impossible. Ton message n’a pas été envoyé.');
    } on ApiException catch (e) {
      if (e.statusCode == 404 && e.code == 'tirage_not_found') {
        // T3 — le tirage rattaché n'existe plus côté serveur. Aucun crédit n'a
        // été consommé (garanti backend). On abandonne le contexte tirage et on
        // laisse l'utilisateur réessayer / continuer sans lui — pas de crash,
        // pas de boucle.
        if (!mounted) return;
        setState(() {
          _sending = false;
          _pendingTirageId = null;
          _networkError =
              "Ce tirage n'est plus disponible. Tu peux revenir à ton "
              'tirage ou continuer la conversation.';
        });
        return;
      }
      _failNetwork('Le serveur n’a pas répondu. Réessaie dans un instant.');
    } catch (_) {
      _failNetwork('Une erreur est survenue. Réessaie.');
    }
  }

  QuotaDto? _quotaFrom(Map<String, dynamic> body) {
    final q = body['quota'];
    return q is Map<String, dynamic> ? QuotaDto.fromJson(q) : null;
  }

  void _failNetwork(String message) {
    if (!mounted) return;
    setState(() {
      _sending = false;
      _networkError = message; // _pending conservé -> retry sans duplication
    });
  }

  Future<void> _goToLogin(AuthController auth) async {
    await auth.invalidateSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
      (route) => false,
    );
  }

  Future<bool?> _confirmFirstMessage() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AuryelColors.surface,
        title: Text(
          'Ouvrir une consultation',
          style: AuryelText.display(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Cette conversation ouvrira une consultation de 2 h.',
          style: AuryelText.body(
            fontSize: 13.5,
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
              'Commencer',
              style: AuryelText.body(
                color: AuryelColors.goldLight,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// TIMER-D.1 — `seconds` = portefeuille de temps TOTAL (`time.total`), pas un
  /// countdown de session de 2 h.
  static String formatRemaining(int seconds) {
    if (seconds <= 0) return 'Temps de consultation épuisé';
    return 'Temps de consultation · ${ConsultationController.formatTotalTime(seconds)}';
  }

  String _statusLine() {
    final c = _consultation;
    if (c == null) return 'Prêt·e à échanger avec ${_headerAdvisor.name}';
    // Le total vient du contrôleur (bloc `time`) quand il est monté ; sinon
    // fallback sur `seconds_remaining` de la réponse (déjà le total).
    final controller = ConsultationScope.maybeReadOf(context);
    final total = controller?.time?.totalRemainingSeconds ?? c.secondsRemaining;
    return formatRemaining(total);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              _Header(advisor: _headerAdvisor, statusLine: _statusLine()),
              if (_historyLoading || _historyError)
                _HistoryNotice(
                  error: _historyError,
                  onRetry: _historyError ? _retryHistory : null,
                ),
              Expanded(child: _messageList()),
              if (_noCredit)
                _NoCreditPanel(
                  quota: _noCreditQuota,
                  onClose: () => Navigator.of(context).maybePop(),
                )
              else
                _InputBar(
                  controller: _input,
                  enabled: _pending == null && !_sending,
                  canSend: _canSend,
                  sending: _sending,
                  error: _networkError,
                  onSend: _onSendPressed,
                  onChanged: () => setState(() {}),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageList() {
    final items = <Widget>[
      for (final m in _messages) _Bubble(fromUser: m.fromUser, text: m.text),
      if (_pending != null)
        _Bubble(fromUser: true, text: _pending!, pending: true),
      if (_sending) const _TypingIndicator(),
    ];
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Écris ton premier message pour commencer.',
            textAlign: TextAlign.center,
            style: AuryelText.body(fontSize: 13, color: AuryelColors.textMuted),
          ),
        ),
      );
    }
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      children: items,
    );
  }
}

// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.advisor, required this.statusLine});

  final AdvisorInfo advisor;
  final String statusLine;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AuryelColors.warmBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.arrow_back_ios_new,
              size: 18,
              color: AuryelColors.textMuted,
            ),
          ),
          Container(
            width: 40,
            height: 40,
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AuryelColors.goldGradient,
            ),
            child: ClipOval(
              child: Image.asset(advisor.assetPath, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  advisor.name,
                  style: AuryelText.display(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AuryelText.body(
                    fontSize: 11.5,
                    color: AuryelColors.goldLight,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bandeau discret sous l'en-tête : chargement de l'historique en cours, ou
/// échec rejouable. Ne remplace jamais la saisie — le chat reste utilisable.
class _HistoryNotice extends StatelessWidget {
  const _HistoryNotice({required this.error, this.onRetry});

  final bool error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 8, 10, 8),
      color: AuryelColors.surface.withValues(alpha: 0.5),
      child: Row(
        children: [
          if (!error) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: AuryelColors.gold,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              error
                  ? 'Historique indisponible pour le moment.'
                  : 'Chargement de ta conversation…',
              style: AuryelText.body(
                fontSize: 11.5,
                color: AuryelColors.textMuted,
              ),
            ),
          ),
          if (error && onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Réessayer',
                style: AuryelText.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.goldLight,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.fromUser,
    required this.text,
    this.pending = false,
  });

  final bool fromUser;
  final String text;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        decoration: BoxDecoration(
          color: fromUser
              ? AuryelColors.gold.withValues(alpha: pending ? 0.10 : 0.16)
              : AuryelColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: fromUser
                ? AuryelColors.gold.withValues(alpha: 0.35)
                : AuryelColors.warmBorder,
          ),
        ),
        child: Text(
          text,
          style: AuryelText.body(
            fontSize: 14,
            height: 1.4,
            color: pending ? AuryelColors.textMuted : AuryelColors.textCream,
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AuryelColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AuryelColors.warmBorder),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AuryelColors.gold,
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.canSend,
    required this.sending,
    required this.error,
    required this.onSend,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool canSend;
  final bool sending;
  final String? error;
  final VoidCallback onSend;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
      decoration: BoxDecoration(
        color: AuryelColors.surface,
        border: Border(top: BorderSide(color: AuryelColors.warmBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (error != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      error!,
                      style: AuryelText.body(
                        fontSize: 12,
                        color: AuryelColors.goldLight,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: sending ? null : onSend,
                    child: Text(
                      'Réessayer',
                      style: AuryelText.body(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.goldLight,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: enabled,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    style: AuryelText.body(
                      fontSize: 14,
                      color: AuryelColors.textCream,
                    ),
                    cursorColor: AuryelColors.gold,
                    onChanged: (_) => onChanged(),
                    onSubmitted: (_) {
                      if (canSend) onSend();
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Écris ton message…',
                      hintStyle: AuryelText.body(
                        fontSize: 14,
                        color: AuryelColors.textMuted,
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AuryelColors.warmBorder),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: AuryelColors.gold,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: canSend ? onSend : null,
                  icon: Icon(
                    Icons.send_rounded,
                    color: canSend
                        ? AuryelColors.gold
                        : AuryelColors.textMuted.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoCreditPanel extends StatelessWidget {
  const _NoCreditPanel({required this.quota, required this.onClose});

  final QuotaDto? quota;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      decoration: BoxDecoration(
        color: AuryelColors.surface,
        border: Border(top: BorderSide(color: AuryelColors.warmBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // TIMER-D.1 — texte V1 « temps épuisé » (plus « consultations »).
              quota?.isPremium == true
                  ? 'Ton temps de consultation disponible est épuisé.'
                  : 'Ton temps de consultation est épuisé.',
              style: AuryelText.display(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Premium — 7,99 €/mois',
              style: AuryelText.body(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AuryelColors.goldLight,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '8 h de consultation par mois · messages illimités pendant chaque consultation',
              style: AuryelText.body(
                fontSize: 13,
                color: AuryelColors.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                TextButton(
                  onPressed: onClose,
                  child: Text(
                    'Retour',
                    style: AuryelText.body(color: AuryelColors.textMuted),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PremiumScreen()),
                  ),
                  child: Text(
                    'Découvrir Premium',
                    style: AuryelText.body(
                      fontWeight: FontWeight.w600,
                      color: AuryelColors.goldLight,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
