import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/ai_report_api.dart';
import '../api/api_client.dart';
import '../data/consultation.dart';
import '../data/content_recommendation.dart';
import '../state/auth_controller.dart';
import '../state/consultation_controller.dart';
import '../state/rewards_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/advisors_carousel.dart';
import '../widgets/ai_report_sheet.dart';
import '../widgets/ai_transparency_note.dart';
import 'adult_gate.dart';
import 'onboarding/email_auth_screen.dart';
import 'premium_screen.dart';
import 'rewards_wallet_screen.dart';
import 'ebook_reader_screen.dart';
import 'meditation_library_screen.dart';
import 'exercise_detail_screen.dart';

/// Délai de présentation naturel après réception de la réponse réelle.
/// Le réseau n’est jamais ralenti : seule l’apparition de la réponse est
/// temporisée pendant que l’indicateur de saisie reste visible.
Duration consultationReplyPresentationDelay(
  String reply, {
  int variationMs = 0,
}) {
  final length = reply.trim().length;
  final base = length < 120
      ? 1800
      : length < 420
      ? 3200
      : 5200;
  return Duration(milliseconds: (base + variationMs).clamp(1500, 8000));
}

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
  const ChatScreen({
    super.key,
    required this.advisor,
    this.consultationId,
    this.tirageId,
    this.initialMessage,
    this.aiReportApi,
  });

  /// Conseiller du fil. Sur le chemin multi-consultations (J6-F2), il est
  /// AUTORITAIRE : il correspond au `advisor_id` du fil ciblé et n'est jamais
  /// remplacé par `AuryelState.selectedAdvisor` ni par `kAdvisors.first`. Sur le
  /// chemin hérité (sans [consultationId]), il sert d'affichage tant que le
  /// backend n'a pas renvoyé de consultation, puis `consultation.advisor_id`
  /// prime.
  final AdvisorInfo advisor;

  /// J6-F2 — identifiant EXACT du fil à reprendre. Fourni, ChatScreen cible ce
  /// fil précis : historique via `?consultation_id=<id>`, chaque envoi porte
  /// `consultation_id`, aucun repli vers « le dernier fil du compte ». Absent
  /// -> comportement hérité (fil courant choisi par le backend).
  final String? consultationId;

  /// Signalement d'une réponse IA. Test uniquement en injection directe ; en
  /// production on retombe sur `AuthScope.maybeOf(context)?.aiReportApi`.
  final AiReportApi? aiReportApi;

  /// T3 — tirage à rattacher à la consultation. Envoyé avec le PREMIER message
  /// tant qu'il n'a pas obtenu un 200 ; ni le passage ici ni le clic du CTA
  /// « En parler avec … » n'ouvrent une consultation ou ne consomment de crédit.
  final String? tirageId;

  /// Contexte préparé par un écran qui souhaite en parler au conseiller.
  /// Il reste un brouillon : aucune consultation ni consommation n’a lieu
  /// avant l’envoi explicite du premier message.
  final String? initialMessage;

  /// Exposé pour les tests : formatage de `seconds_remaining`.
  static String debugFormatRemaining(int seconds) =>
      _ChatScreenState.formatRemaining(seconds);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatMessage {
  const _ChatMessage({
    required this.fromUser,
    required this.text,
    this.messageId,
    this.recommendation,
  });
  final bool fromUser;
  final String text;

  /// Identifiant stable backend de la réponse assistant — sert à cibler le
  /// signalement. `null` pour un message utilisateur ou une réponse d'un
  /// backend qui ne l'expose pas encore (le signalement retombe alors sur le
  /// `consultation_id`).
  final String? messageId;
  final ContentRecommendation? recommendation;
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  final List<_ChatMessage> _messages = [];
  ConsultationDto? _consultation;

  bool _sending = false;
  bool _pendingRewardedMicro = false;
  bool _firstMessageConfirmed = false;

  /// Message en cours d'envoi / en échec — renvoyé tel quel, jamais dupliqué.
  String? _pending;
  String? _pendingIdempotencyKey;
  String? _networkError;

  bool _noCredit = false;
  QuotaDto? _noCreditQuota;

  bool _seeded = false;
  final Set<String> _recommendationBusy = <String>{};

  /// Chargement de l'historique backend : tenté au plus une fois par ouverture
  /// (le retry remet le drapeau à `false`). `_historyLoading` / `_historyError`
  /// ne pilotent qu'un bandeau discret — jamais le blocage de la saisie.
  AuthController? _auth;
  bool _historyRequested = false;
  bool _historyLoading = false;
  bool _historyError = false;
  Timer? _replyDelayTimer;
  Completer<void>? _replyDelayCompleter;

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
    _input.text = widget.initialMessage?.trim() ?? '';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    _auth = AuthScope.maybeOf(context);

    // J6-F2 — fil ciblé explicitement : on reprend CE fil, jamais « le dernier
    // du compte ». Le conseiller fourni fait autorité. Historique en lecture
    // seule via `?consultation_id=<id>`.
    if (widget.consultationId != null && widget.consultationId!.isNotEmpty) {
      _firstMessageConfirmed = true; // fil existant -> pas de confirmation
      _loadHistory();
      return;
    }

    // F4 / TIMER-D.1 — reprise d'une consultation LOGIQUE déjà ouverte : on
    // part du state partagé, pas d'un écran vierge. `hasResumableConsultation`
    // (et non `hasActiveSession`) : l'historique reste visible même hors
    // fenêtre de 5 min et même si le portefeuille de temps est bas. Lecture
    // seule, aucun POST.
    final controller = ConsultationScope.maybeReadOf(context);
    if (controller != null && controller.hasResumableConsultation) {
      _consultation = controller.active;
      _firstMessageConfirmed =
          true; // consultation existante -> pas de confirmation
      _loadHistory();
    }
  }

  /// Identifiant du fil courant : le fil ciblé (J6-F2) prime, sinon la
  /// consultation logique du state partagé.
  String? get _threadId => widget.consultationId ?? _consultation?.id;

  /// Charge l'historique de la consultation active. Lecture seule : aucun
  /// crédit, aucun POST. N'injecte les messages QUE si le `consultation_id`
  /// renvoyé correspond à la session active. Idempotent tant que
  /// `_historyRequested` est vrai (protège contre un `didChangeDependencies`
  /// rappelé).
  Future<void> _loadHistory() async {
    if (_historyRequested) return;
    final auth = _auth;
    final activeId = _threadId;
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
      // J6-F2 — toujours cibler le fil réellement repris. Le chemin issu de
      // l'état partagé possède lui aussi un identifiant fiable (`activeId`) :
      // ne pas retomber sur le choix serveur du « dernier fil ».
      final res = await auth.consultationApi.getMessages(
        bearer: token,
        consultationId: activeId,
      );
      if (!mounted) return;

      // consultation_id inattendu / inaccessible -> on n'injecte AUCUN message
      // (jamais l'historique d'un autre fil), et on affiche le bandeau d'erreur
      // contrôlée si le fil ciblé est introuvable.
      if (res.consultationId == null || res.consultationId != activeId) {
        if (widget.consultationId != null) {
          _failHistory();
          return;
        }
        setState(() => _historyLoading = false);
        return;
      }

      final restored = <_ChatMessage>[
        for (final m in res.messages)
          if (m.content.trim().isNotEmpty)
            _ChatMessage(
              fromUser: m.isUser,
              text: m.content,
              messageId: m.messageId,
              recommendation: m.recommendation,
            ),
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
    _replyDelayTimer?.cancel();
    _replyDelayCompleter?.complete();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  AdvisorInfo get _headerAdvisor {
    // J6-F2 — fil ciblé : le conseiller fourni fait autorité (il correspond au
    // `advisor_id` du fil). Aucun repli vers `selectedAdvisor` / `kAdvisors`.
    if (widget.consultationId != null) return widget.advisor;
    return advisorByGuideKey(_consultation?.advisorId) ?? widget.advisor;
  }

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
      // Clé opaque, stable pour cette tentative et indépendante du contenu
      // sensible du message. Elle est conservée sur retry/timeout/402.
      _pendingIdempotencyKey = generateIdempotencyKey('consultation_message');
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
        // J6-F2 — chemin multi-consultations : chaque envoi cible le fil exact.
        // Chemin hérité (consultationId null) : body inchangé.
        consultationId: widget.consultationId,
        tirageId: _pendingTirageId,
        idempotencyKey: _pendingIdempotencyKey,
        rewardedMicro: _pendingRewardedMicro,
      );
      if (!mounted) return;
      await _waitBeforeShowingReply(res.reply);
      if (!mounted) return;
      final showCreditChoices =
          _pendingRewardedMicro && (res.time?.totalRemainingSeconds ?? 0) <= 0;
      // F4 — l'état renvoyé alimente aussi le state partagé de l'app.
      consultation?.updateFromMessageResponse(res);
      setState(() {
        _messages.add(
          _ChatMessage(fromUser: true, text: displayMessageContent(_pending!)),
        );
        _messages.add(
          _ChatMessage(
            fromUser: false,
            text: res.reply,
            messageId: res.replyMessageId,
            recommendation: res.recommendation,
          ),
        );
        _consultation = res.consultation ?? _consultation;
        _pending = null;
        _pendingIdempotencyKey = null;
        _pendingRewardedMicro = false;
        _sending = false;
        _noCredit = showCreditChoices;
        _noCreditQuota = showCreditChoices ? res.quota : null;
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
        // Le brouillon et sa clé restent associés à cette tentative : après
        // un droit confirmé, l'utilisateur pourra appuyer explicitement sur
        // Envoyer, sans recréer une intention ni perdre son texte.
        _pending = text;
        _noCredit = true;
        _noCreditQuota = quota;
      });
    } on ApiForbiddenException catch (e) {
      if (!mounted) return;
      final code = e.code ?? e.body['error']?.toString();
      if (code == 'age_verification_required' || code == 'adult_required') {
        // Ce N'EST PAS une panne serveur : aucun « le serveur n'a pas
        // répondu », aucun retry. On renvoie vers le parcours 18+ existant
        // (AdultGate), qui refait autorité serveur et route vers `needsDob`
        // (`age_verification_required`) ou l'écran bloqué (`adult_required`).
        _routeToAgeGate();
      } else {
        // Autre 403 (hors périmètre de ce lot) : comportement inchangé.
        _failNetwork('Le serveur n’a pas répondu. Réessaie dans un instant.');
      }
    } on ApiNetworkException {
      _failNetwork('Connexion impossible. Ton message n’a pas été envoyé.');
    } on ApiException catch (e) {
      if (e.code == 'consultation_request_processing') {
        _failNetwork(
          'Ta demande est encore en cours. Réessaie dans un instant.',
        );
        return;
      }
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

  Future<void> _waitBeforeShowingReply(String reply) {
    final delay = consultationReplyPresentationDelay(reply);
    final completer = Completer<void>();
    _replyDelayTimer?.cancel();
    _replyDelayCompleter?.complete();
    _replyDelayCompleter = completer;
    _replyDelayTimer = Timer(delay, () {
      _replyDelayTimer = null;
      _replyDelayCompleter = null;
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  QuotaDto? _quotaFrom(Map<String, dynamic> body) {
    final q = body['quota'];
    if (q is! Map<String, dynamic>) return null;
    // Le 402 porte le solde Rewarded au niveau racine pour préserver le
    // contrat historique de `quota`. On le fusionne uniquement pour l'UX :
    // la décision d'accorder le droit reste serveur.
    final rewarded = body['rewarded'];
    if (rewarded is Map<String, dynamic> &&
        !q.containsKey('questions_available')) {
      return QuotaDto.fromJson({...q, 'rewarded': rewarded});
    }
    return QuotaDto.fromJson(q);
  }

  void _failNetwork(String message) {
    if (!mounted) return;
    setState(() {
      _sending = false;
      _networkError = message; // _pending conservé -> retry sans duplication
    });
  }

  Future<void> _openCreditPath(
    Widget destination, {
    bool rewarded = false,
  }) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => destination));
    if (!mounted) return;
    final consultation = ConsultationScope.maybeReadOf(context);
    final rewards = RewardsScope.maybeReadOf(context);
    await consultation?.refresh();
    await rewards?.refresh();
    if (!mounted) return;
    final seconds = consultation?.time?.totalRemainingSeconds ?? 0;
    final questions =
        rewards?.questionsAvailable ??
        consultation?.quota?.questionsAvailable ??
        0;
    if (seconds > 0 || questions > 0) {
      setState(() {
        _noCredit = false;
        if (rewarded) _pendingRewardedMicro = true;
        _noCreditQuota = null;
        _networkError = null;
      });
    }
  }

  Future<void> _goToLogin(AuthController auth) async {
    await auth.invalidateSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
      (route) => false,
    );
  }

  /// Refus 403 lié à l'âge sur une mutation de consultation. Le message n'est
  /// PAS parti (aucune bulle). On réutilise [AdultGate] — pas de second système
  /// d'âge : `forceServerCheck` lui fait refaire autorité serveur, puis il
  /// route lui-même vers `needsDob` (`age_verification_required`) ou vers
  /// l'écran bloqué (`adult_required`).
  void _routeToAgeGate() {
    setState(() {
      _sending = false;
      _pending = null; // le message n'a pas été envoyé
      _networkError = null;
    });
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const AdultGate(forceServerCheck: true),
      ),
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
          'Ce premier message ouvre ta consultation. Le temps se décompte '
          'ensuite de ton temps disponible.',
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

  /// Signalement d'UNE réponse conseiller/IA (jamais un message utilisateur).
  /// La feuille ne confirme qu'en cas de 2xx serveur réel ; sinon elle reste
  /// ouverte avec un message d'erreur (aucun faux succès).
  ///
  /// [messageId] : identifiant stable de la réponse ciblée quand le backend
  /// l'a fourni. `null` pour une réponse ancienne -> le signalement reste
  /// exploitable via `consultation_id` seul (jamais de `message_id` inventé).
  Future<void> _reportResponse(String? messageId) async {
    final auth = AuthScope.maybeOf(context);
    final api = widget.aiReportApi ?? auth?.aiReportApi;
    final consultationId =
        _threadId ?? ConsultationScope.maybeReadOf(context)?.active?.id;
    final messenger = ScaffoldMessenger.of(context);

    final submitted = await showAiReportSheet(
      context,
      onSubmit: (reason, comment) async {
        if (api == null || auth == null) return false; // pas de faux succès
        final token = await auth.currentToken();
        if (token == null || token.isEmpty) return false;
        try {
          await api.report(
            bearer: token,
            reason: reason,
            // `message_id` cible la réponse exacte quand il existe ; sinon
            // `AiReportApi` l'omet et `consultation_id` sert de contexte.
            messageId: messageId,
            consultationId: consultationId,
            comment: comment,
          );
          return true;
        } catch (_) {
          return false;
        }
      },
    );
    if (!mounted || !submitted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Merci. Ton signalement a bien été transmis.'),
      ),
    );
  }

  void _scrollToEnd() {
    void settle(int attempt) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // History insertion can trigger more than one layout pass. Do not
        // commit to an extent of zero while the restored children are still
        // being laid out.
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        if (!_scroll.hasClients && attempt < 4) {
          settle(attempt + 1);
          return;
        }
        if (!_scroll.hasClients) return;
        if (_scroll.position.maxScrollExtent == 0 && attempt < 4) {
          settle(attempt + 1);
          return;
        }
        await _scroll.animateTo(
          _scroll.position.minScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    }

    settle(0);
  }

  /// TIMER-D.1/D.2 — `seconds` = portefeuille de temps TOTAL (`time.total`).
  /// « 7 h 42 min disponibles » / « Temps de consultation épuisé ». Jamais de
  /// countdown seconde par seconde.
  static String formatRemaining(int seconds) {
    if (seconds <= 0) return 'Temps de consultation épuisé';
    return '${ConsultationController.formatTotalTime(seconds)} disponibles';
  }

  /// TIMER-D.2 — statut d'en-tête :
  ///  - fenêtre active  -> « Consultation en cours · X h Y min disponibles »
  ///  - hors fenêtre    -> « X h Y min disponibles » (jamais « expirée »)
  ///  - temps épuisé    -> « Temps de consultation épuisé »
  ///  - pas de consultation -> invite d'ouverture.
  String _statusLine() {
    final c = _consultation;
    if (c == null) return 'Prêt·e à échanger avec ${_headerAdvisor.name}';
    final controller = ConsultationScope.maybeReadOf(context);
    final total = controller?.time?.totalRemainingSeconds ?? c.secondsRemaining;
    final base = formatRemaining(total);
    if ((controller?.windowActive ?? false) && total > 0) {
      return 'Consultation en cours · $base';
    }
    return base;
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
              // Transparence IA — toujours visible, jamais masquée (exigence
              // Google Play : contenu généré par IA).
              const AiTransparencyNote(
                padding: EdgeInsets.fromLTRB(18, 4, 18, 2),
              ),
              if (_historyLoading || _historyError)
                _HistoryNotice(
                  error: _historyError,
                  onRetry: _historyError ? _retryHistory : null,
                ),
              Expanded(child: _messageList()),
              if (_noCredit)
                _NoCreditPanel(
                  quota: _noCreditQuota,
                  onClose: () => setState(() => _noCredit = false),
                  onPremium: () => _openCreditPath(const PremiumScreen()),
                  onExtraHour: () =>
                      _openCreditPath(const ExtraHourPurchaseScreen()),
                  onUseQuestion: () => setState(() => _noCredit = false),
                  onRewarded: () => _openCreditPath(
                    const RewardsWalletScreen(),
                    rewarded: true,
                  ),
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

  void _recordRecommendationEvent(
    ContentRecommendation recommendation,
    String event,
  ) {
    final auth = _auth;
    if (auth == null) return;
    unawaited(() async {
      try {
        final token = await auth.currentToken();
        if (token == null || token.isEmpty) return;
        await auth.consultationApi.recordRecommendationEvent(
          bearer: token,
          recommendationId: recommendation.recommendationId,
          event: event,
        );
      } catch (_) {
        // Tracking is best effort and never blocks reading or navigation.
      }
    }());
  }

  Future<void> _openRecommendation(ContentRecommendation recommendation) async {
    _recordRecommendationEvent(recommendation, 'opened');
    if (!mounted) return;
    if (recommendation.isEbook) {
      final url = recommendation.pdfUrl;
      if (url == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ce guide est momentanément indisponible.'),
          ),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              EbookReaderScreen(title: recommendation.title, url: url),
        ),
      );
      return;
    }
    if (recommendation.isMeditation) {
      await openVideoMeditationLibrary(context);
      return;
    }
    final exercise = recommendation.asExercise();
    if (exercise == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExerciseDetailScreen(exercise: exercise),
      ),
    );
  }

  Future<void> _downloadRecommendation(
    ContentRecommendation recommendation,
  ) async {
    if (!recommendation.isEbook ||
        _recommendationBusy.contains(recommendation.recommendationId)) {
      return;
    }
    final url = recommendation.pdfUrl;
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Le téléchargement est momentanément indisponible.'),
          ),
        );
      }
      return;
    }
    setState(() => _recommendationBusy.add(recommendation.recommendationId));
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          response.bodyBytes.isEmpty) {
        throw const HttpException('download');
      }
      final directory = await getTemporaryDirectory();
      final safeName = recommendation.title
          .replaceAll(RegExp(r'[^a-zA-Z0-9À-ÿ]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '')
          .toLowerCase();
      final file = File(
        '${directory.path}/${safeName.isEmpty ? 'auryel_ebook' : safeName}.pdf',
      );
      await file.writeAsBytes(response.bodyBytes, flush: true);
      _recordRecommendationEvent(recommendation, 'download_requested');
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: recommendation.title),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de télécharger ce PDF pour le moment.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(
          () => _recommendationBusy.remove(recommendation.recommendationId),
        );
      }
    }
  }

  Widget _messageList() {
    final items = <Widget>[
      for (final m in _messages)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Bubble(
              fromUser: m.fromUser,
              text: m.text,
              // Signalement possible UNIQUEMENT sur une réponse conseiller/IA.
              onReport: m.fromUser ? null : () => _reportResponse(m.messageId),
            ),
            if (!m.fromUser && m.recommendation != null)
              RecommendationCard(
                recommendation: m.recommendation!,
                busy: _recommendationBusy.contains(
                  m.recommendation!.recommendationId,
                ),
                onOpen: () => _openRecommendation(m.recommendation!),
                onDownload: () => _downloadRecommendation(m.recommendation!),
              ),
          ],
        ),
      if (_pending != null)
        _Bubble(
          fromUser: true,
          text: displayMessageContent(_pending!),
          pending: true,
        ),
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
      reverse: true,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      children: items.reversed.toList(growable: false),
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
    this.onReport,
  });

  final bool fromUser;
  final String text;
  final bool pending;

  /// Non nul UNIQUEMENT sur une réponse conseiller/IA -> action « ⋯ » discrète.
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
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
    );

    if (onReport == null) {
      return Align(
        alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
        child: bubble,
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(child: bubble),
          _ReportMenuButton(onReport: onReport!),
        ],
      ),
    );
  }
}

/// Bouton « ⋯ » discret sur une réponse IA -> menu « Signaler cette réponse ».
class _ReportMenuButton extends StatelessWidget {
  const _ReportMenuButton({required this.onReport});

  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Options de la réponse',
      icon: const Icon(
        Icons.more_horiz,
        size: 18,
        color: AuryelColors.textMuted,
      ),
      color: AuryelColors.surface,
      onSelected: (v) {
        if (v == 'report') onReport();
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'report',
          child: Text(
            'Signaler cette réponse',
            style: AuryelText.body(fontSize: 13, color: AuryelColors.textCream),
          ),
        ),
      ],
    );
  }
}

class RecommendationCard extends StatelessWidget {
  const RecommendationCard({
    super.key,
    required this.recommendation,
    required this.onOpen,
    required this.onDownload,
    required this.busy,
  });

  final ContentRecommendation recommendation;
  final VoidCallback onOpen;
  final VoidCallback onDownload;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final isEbook = recommendation.isEbook;
    final isMeditationNavigation =
        recommendation.isMeditation && recommendation.navigationOnly;
    final image = recommendation.coverUrl ?? recommendation.imageUrl;
    return Container(
      margin: const EdgeInsets.only(left: 2, right: 34, top: 2, bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AuryelColors.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AuryelColors.gold.withValues(alpha: 0.38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RecommendationImage(url: image, ebook: isEbook),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recommendation.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AuryelText.body(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (recommendation.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    recommendation.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AuryelText.body(
                      fontSize: 11,
                      color: AuryelColors.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    OutlinedButton(
                      onPressed: onOpen,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AuryelColors.goldLight,
                        side: const BorderSide(color: AuryelColors.gold),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        isEbook
                            ? 'Lire dans Auryel'
                            : recommendation.isMeditation
                            ? isMeditationNavigation
                                  ? 'Voir les méditations'
                                  : 'Écouter'
                            : "Faire l'exercice",
                      ),
                    ),
                    if (isEbook)
                      TextButton.icon(
                        onPressed: busy ? null : onDownload,
                        icon: busy
                            ? const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                ),
                              )
                            : const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Télécharger le PDF'),
                        style: TextButton.styleFrom(
                          foregroundColor: AuryelColors.textMuted,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationImage extends StatelessWidget {
  const _RecommendationImage({this.url, required this.ebook});
  final String? url;
  final bool ebook;

  @override
  Widget build(BuildContext context) {
    final child = url == null
        ? Icon(
            ebook ? Icons.menu_book_rounded : Icons.self_improvement_rounded,
            color: AuryelColors.goldLight,
            size: 28,
          )
        : Image.network(
            url!,
            fit: BoxFit.cover,
            errorBuilder: (_, error, stack) => Icon(
              ebook ? Icons.menu_book_rounded : Icons.self_improvement_rounded,
              color: AuryelColors.goldLight,
              size: 28,
            ),
          );
    return Container(
      width: ebook ? 62 : 58,
      height: 78,
      decoration: BoxDecoration(
        color: AuryelColors.backgroundDeep,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: child,
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
  const _NoCreditPanel({
    required this.quota,
    required this.onClose,
    required this.onPremium,
    required this.onExtraHour,
    required this.onUseQuestion,
    required this.onRewarded,
  });

  final QuotaDto? quota;
  final VoidCallback onClose;
  final VoidCallback onPremium;
  final VoidCallback onExtraHour;
  final VoidCallback onUseQuestion;
  final VoidCallback onRewarded;

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
              'Continuez votre consultation',
              style: AuryelText.display(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Votre temps de consultation est épuisé. Choisissez comment continuer avec votre conseiller.',
              style: AuryelText.body(
                fontSize: 13,
                color: AuryelColors.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPremium,
                child: const Text('Passer Premium'),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '4 h de consultation par mois • Sans publicité',
              style: AuryelText.body(
                fontSize: 12,
                color: AuryelColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onExtraHour,
                child: const Text('Ajouter 1 heure'),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '+1 h de consultation',
              style: AuryelText.body(
                fontSize: 12,
                color: AuryelColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: (quota?.questionsAvailable ?? 0) > 0
                    ? onUseQuestion
                    : onRewarded,
                child: Text(
                  (quota?.questionsAvailable ?? 0) > 0
                      ? 'Utiliser ma question'
                      : 'Regarder une publicité',
                ),
              ),
            ),
            if ((quota?.questionsAvailable ?? 0) == 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Regardez une courte publicité pour poser 1 question à votre conseiller.',
                  style: AuryelText.body(
                    fontSize: 12,
                    color: AuryelColors.textMuted,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${quota!.questionsAvailable} question${quota!.questionsAvailable > 1 ? 's' : ''} disponible${quota!.questionsAvailable > 1 ? 's' : ''}.',
                  style: AuryelText.body(
                    fontSize: 12,
                    color: AuryelColors.textMuted,
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onClose,
                child: Text(
                  'Retour',
                  style: AuryelText.body(color: AuryelColors.textMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
