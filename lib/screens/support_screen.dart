import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../api/api_client.dart';
import '../api/support_api.dart';
import '../config/app_info.dart';
import '../state/auth_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/gold_button.dart';

/// « Signaler un problème » — formulaire in-app envoyé au backend
/// (`POST /api/app/support`). L'adresse email du compte est connue côté serveur
/// : on ne la redemande pas. Aucune donnée sensible n'est jointe.
///
/// Ne dépend PAS d'une app email installée sur le téléphone.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, this.apiOverride});

  /// Test uniquement : sinon lu depuis `AuthScope.of(context).supportApi`.
  final SupportApi? apiOverride;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

enum _Phase { form, sending, sent }

class _SupportScreenState extends State<SupportScreen> {
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  SupportCategory _category = SupportCategory.account;

  _Phase _phase = _Phase.form;
  String? _error;

  static const _subjectMax = 140;
  static const _messageMax = 4000;

  bool get _valid =>
      _subjectCtrl.text.trim().isNotEmpty &&
      _subjectCtrl.text.trim().length <= _subjectMax &&
      _messageCtrl.text.trim().isNotEmpty &&
      _messageCtrl.text.trim().length <= _messageMax;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  String get _platformLabel {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return defaultTargetPlatform.name;
    }
  }

  Future<void> _submit() async {
    if (!_valid || _phase == _Phase.sending) return;
    FocusScope.of(context).unfocus();
    final auth = AuthScope.of(context);
    final api = widget.apiOverride ?? auth.supportApi;
    final token = await auth.currentToken();
    if (!mounted) return;
    if (api == null || token == null || token.isEmpty) {
      setState(() => _error =
          'Impossible d’envoyer votre message pour le moment. Réessayez plus '
          'tard.');
      return;
    }
    setState(() {
      _phase = _Phase.sending;
      _error = null;
    });
    try {
      await api.submit(
        bearer: token,
        subject: _subjectCtrl.text,
        message: _messageCtrl.text,
        category: _category,
        appVersion: kAppVersion,
        platform: _platformLabel,
      );
      if (!mounted) return;
      setState(() => _phase = _Phase.sent);
    } on ApiException catch (_) {
      _fail();
    } on ApiNetworkException catch (_) {
      _fail();
    } catch (_) {
      _fail();
    }
  }

  void _fail() {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.form;
      _error =
          'Impossible d’envoyer votre message pour le moment. Réessayez plus '
          'tard.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const PhosphorIcon(
                      PhosphorIconsRegular.arrowLeft,
                      size: 20,
                      color: AuryelColors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Signaler un problème',
                  style: AuryelText.display(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.textCream,
                  ),
                ),
                const SizedBox(height: 18),
                if (_phase == _Phase.sent)
                  _SentView(onBack: () => Navigator.of(context).maybePop())
                else
                  _formBody(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _formBody() {
    final sending = _phase == _Phase.sending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Décris ton problème : nous te répondons par email, à l’adresse de '
          'ton compte Auryel.',
          style: AuryelText.body(
            fontSize: 12.5,
            height: 1.5,
            color: AuryelColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        _label('CATÉGORIE'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AuryelColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AuryelColors.warmBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<SupportCategory>(
              value: _category,
              isExpanded: true,
              dropdownColor: AuryelColors.surface,
              iconEnabledColor: AuryelColors.textMuted,
              style: AuryelText.body(
                fontSize: 13.5,
                color: AuryelColors.textCream,
              ),
              onChanged: sending
                  ? null
                  : (v) => setState(() => _category = v ?? _category),
              items: [
                for (final c in SupportCategory.values)
                  DropdownMenuItem(value: c, child: Text(c.label)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _label('SUJET'),
        const SizedBox(height: 6),
        TextField(
          controller: _subjectCtrl,
          enabled: !sending,
          maxLength: _subjectMax,
          onChanged: (_) => setState(() => _error = null),
          style: AuryelText.body(fontSize: 14, color: AuryelColors.textCream),
          cursorColor: AuryelColors.gold,
          decoration: _fieldDecoration('Résume ton problème'),
        ),
        const SizedBox(height: 10),
        _label('DESCRIPTION'),
        const SizedBox(height: 6),
        TextField(
          controller: _messageCtrl,
          enabled: !sending,
          maxLength: _messageMax,
          maxLines: 6,
          minLines: 4,
          onChanged: (_) => setState(() => _error = null),
          style: AuryelText.body(fontSize: 14, color: AuryelColors.textCream),
          cursorColor: AuryelColors.gold,
          decoration: _fieldDecoration('Explique ce qui se passe'),
        ),
        const SizedBox(height: 4),
        Text(
          'Version $kAppVersion — $_platformLabel. Ton identifiant de compte '
          'est joint pour nous aider. Aucun mot de passe ni contenu de '
          'consultation n’est transmis.',
          style: AuryelText.body(
            fontSize: 10.5,
            height: 1.4,
            color: AuryelColors.textMuted,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            style: AuryelText.body(
              fontSize: 12.5,
              color: AuryelColors.goldLight,
            ),
          ),
        ],
        const SizedBox(height: 20),
        AuryelGoldButton(
          label: sending ? 'Envoi…' : 'Envoyer',
          onTap: _submit,
          enabled: _valid && !sending,
        ),
      ],
    );
  }

  Widget _label(String text) => Text(
        text,
        style: AuryelText.body(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: AuryelColors.gold,
          letterSpacing: 1.4,
        ),
      );

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AuryelText.body(
          fontSize: 14,
          color: AuryelColors.textMuted,
        ),
        filled: true,
        fillColor: AuryelColors.surface,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AuryelColors.warmBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AuryelColors.gold, width: 1.4),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AuryelColors.warmBorder),
        ),
      );
}

class _SentView extends StatelessWidget {
  const _SentView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const PhosphorIcon(
          PhosphorIconsRegular.checkCircle,
          size: 32,
          color: AuryelColors.goldLight,
        ),
        const SizedBox(height: 14),
        Text(
          'Votre message a bien été envoyé.',
          style: AuryelText.body(
            fontSize: 14,
            height: 1.5,
            color: AuryelColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Nous te répondons par email à l’adresse de ton compte.',
          style: AuryelText.body(
            fontSize: 12.5,
            height: 1.5,
            color: AuryelColors.textMuted,
          ),
        ),
        const SizedBox(height: 22),
        AuryelGoldButton(label: 'Retour', onTap: onBack),
      ],
    );
  }
}
