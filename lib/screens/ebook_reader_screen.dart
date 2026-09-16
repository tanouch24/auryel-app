import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../theme/auryel_theme.dart';

/// Lecteur interne des guides Bien-être.
class EbookReaderScreen extends StatelessWidget {
  const EbookReaderScreen({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return _invalidDocument();
    }
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: PdfViewer.uri(
        uri,
        params: PdfViewerParams(
          backgroundColor: AuryelColors.backgroundDeep,
          margin: 12,
          errorBannerBuilder: (context, error, stackTrace, documentRef) =>
              _loadError(),
        ),
      ),
    );
  }

  Widget _invalidDocument() => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: _loadError(),
      );

  Widget _loadError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            'Ce guide est momentanément indisponible. Réessaie plus tard.',
            textAlign: TextAlign.center,
            style: AuryelText.body(color: AuryelColors.textSecondary),
          ),
        ),
      );
}
