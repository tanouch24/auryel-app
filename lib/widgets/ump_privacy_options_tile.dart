import 'package:flutter/material.dart';

import '../ads/ad_service.dart';
import '../theme/auryel_theme.dart';

/// Accès durable au formulaire officiel Google UMP, sans état de consentement
/// parallèle stocké par l'application.
class UmpPrivacyOptionsTile extends StatefulWidget {
  const UmpPrivacyOptionsTile({super.key});

  @override
  State<UmpPrivacyOptionsTile> createState() => _UmpPrivacyOptionsTileState();
}

class _UmpPrivacyOptionsTileState extends State<UmpPrivacyOptionsTile> {
  late final Future<bool> _required = AuryelAds.instance
      .privacyOptionsRequired();

  Future<void> _show() async {
    await AuryelAds.instance.showPrivacyOptions();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _required,
    builder: (context, snapshot) {
      if (snapshot.data != true) return const SizedBox.shrink();
      return ListTile(
        key: const Key('ump-privacy-options'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(
          Icons.shield_outlined,
          color: AuryelColors.goldLight,
        ),
        title: const Text('Confidentialité publicitaire'),
        subtitle: const Text('Gérer tes choix de consentement'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _show,
      );
    },
  );
}
