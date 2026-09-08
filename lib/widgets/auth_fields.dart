import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/auryel_theme.dart';

/// Champs partagés par la connexion et la création de compte (AUTH V2) — même
/// DA Auryel : sous-ligne dorée, libellé discret, aucun style « formulaire
/// administratif ». Le mot de passe n'est jamais loggé ni conservé ici.

InputDecoration _authDecoration(
  String label,
  String hint, {
  Widget? suffixIcon,
}) => InputDecoration(
  labelText: label,
  labelStyle: AuryelText.body(fontSize: 12.5, color: AuryelColors.textMuted),
  hintText: hint,
  hintStyle: AuryelText.display(
    fontSize: 19,
    fontWeight: FontWeight.w500,
    color: AuryelColors.textMuted,
  ),
  suffixIcon: suffixIcon,
  enabledBorder: UnderlineInputBorder(
    borderSide: BorderSide(color: AuryelColors.warmBorder),
  ),
  focusedBorder: const UnderlineInputBorder(
    borderSide: BorderSide(color: AuryelColors.gold, width: 1.5),
  ),
);

class AuthEmailField extends StatelessWidget {
  const AuthEmailField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool autofocus;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      autofillHints: const [AutofillHints.email],
      style: AuryelText.display(fontSize: 19, fontWeight: FontWeight.w500),
      cursorColor: AuryelColors.gold,
      onChanged: (_) => onChanged(),
      onSubmitted: (_) => onSubmitted(),
      decoration: _authDecoration('Email', 'toi@exemple.com'),
    );
  }
}

class AuthPasswordField extends StatelessWidget {
  const AuthPasswordField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.obscure,
    required this.newPassword,
    required this.onToggleObscure,
    required this.onChanged,
    required this.onSubmitted,
    this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final bool obscure;

  /// `true` en création de compte -> `AutofillHints.newPassword` ;
  /// `false` en connexion -> `AutofillHints.password`.
  final bool newPassword;
  final VoidCallback onToggleObscure;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscure,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: [
        newPassword ? AutofillHints.newPassword : AutofillHints.password,
      ],
      // On ne « normalise » jamais le mot de passe ; on empêche juste un
      // collage accidentel avec un bloc d'espaces multiples.
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s{2,}'))],
      style: AuryelText.display(fontSize: 19, fontWeight: FontWeight.w500),
      cursorColor: AuryelColors.gold,
      onChanged: (_) => onChanged(),
      onSubmitted: (_) => onSubmitted(),
      decoration: _authDecoration(
        'Mot de passe',
        '••••••••',
        suffixIcon: IconButton(
          onPressed: onToggleObscure,
          tooltip: obscure
              ? 'Afficher le mot de passe'
              : 'Masquer le mot de passe',
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 20,
            color: AuryelColors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Lien secondaire discret (« Créer un compte », « J'ai déjà un compte »…).
class AuthSecondaryLink extends StatelessWidget {
  const AuthSecondaryLink({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8),
          minimumSize: const Size(0, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: AuryelText.body(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AuryelColors.goldLight,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
