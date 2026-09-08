import 'package:flutter/material.dart';

import '../api/ai_report_api.dart';
import '../theme/auryel_theme.dart';

/// Feuille « Signaler cette réponse » (exigence Google Play — signalement du
/// contenu IA). Ne concerne QUE les réponses conseiller/IA.
///
/// [onSubmit] renvoie `true` si le serveur a bien accepté le signalement
/// (2xx), `false` sinon. La feuille ne se ferme QUE sur `true` — jamais de faux
/// succès. Le double envoi est bloqué pendant l'appel.
typedef AiReportSubmit = Future<bool> Function(
  AiReportReason reason,
  String? comment,
);

/// Renvoie `true` uniquement si un signalement a été accepté par le serveur
/// (la feuille s'est fermée sur succès). `false` si l'utilisateur a annulé /
/// fermé la feuille sans envoi abouti.
Future<bool> showAiReportSheet(
  BuildContext context, {
  required AiReportSubmit onSubmit,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AiReportSheet(onSubmit: onSubmit),
  );
  return result ?? false;
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected
                    ? AuryelColors.goldLight
                    : AuryelColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: AuryelText.body(
                    fontSize: 13.5,
                    color: AuryelColors.textCream,
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

class _AiReportSheet extends StatefulWidget {
  const _AiReportSheet({required this.onSubmit});

  final AiReportSubmit onSubmit;

  @override
  State<_AiReportSheet> createState() => _AiReportSheetState();
}

class _AiReportSheetState extends State<_AiReportSheet> {
  final TextEditingController _comment = TextEditingController();
  AiReportReason _reason = AiReportReason.inappropriate;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    bool ok = false;
    try {
      ok = await widget.onSubmit(_reason, _comment.text.trim());
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _sending = false;
      _error = 'Impossible d’envoyer le signalement pour le moment. Réessaie plus tard.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: AuryelColors.backgroundGradient,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: AuryelColors.warmBorder, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        // Scrollable : clavier ouvert + petit écran (360 dp) -> pas d'overflow.
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            18,
            24,
            18 + media.viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Signaler cette réponse',
                style: AuryelText.display(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Dis-nous ce qui pose problème. Ton signalement nous aide à '
                'améliorer Auryel.',
                style: AuryelText.body(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AuryelColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              for (final r in AiReportReason.values)
                _ReasonRow(
                  label: r.label,
                  selected: _reason == r,
                  onTap: _sending ? null : () => setState(() => _reason = r),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _comment,
                enabled: !_sending,
                minLines: 1,
                maxLines: 4,
                style: AuryelText.body(
                  fontSize: 13.5,
                  color: AuryelColors.textCream,
                ),
                cursorColor: AuryelColors.gold,
                decoration: InputDecoration(
                  hintText: 'Ajouter un commentaire',
                  hintStyle: AuryelText.body(
                    fontSize: 13.5,
                    color: AuryelColors.textMuted,
                  ),
                  enabledBorder: const UnderlineInputBorder(
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
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: AuryelText.body(
                    fontSize: 12,
                    color: AuryelColors.goldLight,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _sending
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(
                        'Annuler',
                        style: AuryelText.body(color: AuryelColors.textMuted),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _sending ? null : _send,
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: AuryelColors.goldGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            child: Center(
                              child: Text(
                                _sending ? 'Envoi…' : 'Envoyer le signalement',
                                style: AuryelText.body(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AuryelColors.backgroundDeep,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
