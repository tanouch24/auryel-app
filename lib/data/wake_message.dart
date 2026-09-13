/// Message du Réveil Auryel — contenu 100 % distant (`GET
/// /api/app/content/wake-messages`), texte = source de vérité PostgreSQL.
/// `audioUrl` référence un MP3 pré-généré sur Cloudflare R2 : `null` tant
/// qu'il n'existe pas encore pour ce message (repli TextToSpeech local,
/// jamais un appel TTS payant au moment où le réveil sonne).
class WakeMessage {
  const WakeMessage({required this.id, required this.text, this.audioUrl});

  final String id;
  final String text;
  final String? audioUrl;

  /// Parsing TOLÉRANT — `null` si `id`/`text` exploitables manquent (l'entrée
  /// est alors ignorée, jamais de crash).
  static WakeMessage? tryFromJson(Map<String, dynamic> j) {
    final id = (j['id'] is String) ? (j['id'] as String).trim() : '';
    final text = (j['text'] is String) ? (j['text'] as String).trim() : '';
    if (id.isEmpty || text.isEmpty) return null;
    final audio = j['audio_url'];
    return WakeMessage(
      id: id,
      text: text,
      audioUrl: (audio is String && audio.trim().isNotEmpty)
          ? audio.trim()
          : null,
    );
  }

  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'text': text,
    if (audioUrl != null) 'audio_url': audioUrl,
  };
}
