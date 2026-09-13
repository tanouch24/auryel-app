import 'wake_message.dart';

/// Repli EMBARQUÉ du Réveil Auryel — utilisé UNIQUEMENT si l'app n'a encore
/// jamais pu synchroniser le catalogue distant (premier réveil programmé
/// hors ligne, par exemple). Sous-ensemble stable des mêmes phrases que le
/// backend (`wake_messages`, Migration v47) : aucun contenu contradictoire,
/// juste un socle minimal pour ne jamais laisser le réveil muet.
class WakeMessageCatalog {
  const WakeMessageCatalog();

  static const List<WakeMessage> items = [
    WakeMessage(
      id: 'embedded-1',
      text: "Respire doucement avant de te lever. Ce moment n'appartient qu'à toi.",
    ),
    WakeMessage(
      id: 'embedded-2',
      text: 'Cette journée n\'a pas besoin d\'être parfaite pour être bonne.',
    ),
    WakeMessage(
      id: 'embedded-3',
      text: 'Commence doucement. Le reste suivra à son heure.',
    ),
    WakeMessage(
      id: 'embedded-4',
      text: 'Un peu de calme le matin change souvent toute une journée.',
    ),
    WakeMessage(
      id: 'embedded-5',
      text: 'Avance doucement. La constance compte plus que la vitesse.',
    ),
    WakeMessage(
      id: 'embedded-6',
      text: 'Tu peux commencer petit. Ce sera déjà suffisant.',
    ),
    WakeMessage(
      id: 'embedded-7',
      text: "Prends une grande respiration. Tu as le temps de bien démarrer.",
    ),
    WakeMessage(
      id: 'embedded-8',
      text: 'Chaque matin est une occasion simple de recommencer autrement.',
    ),
    WakeMessage(
      id: 'embedded-9',
      text: 'Ce jour t\'offre une page neuve. Écris-la à ton allure.',
    ),
    WakeMessage(
      id: 'embedded-10',
      text: "Aujourd'hui encore, tu as le droit d'avancer à ta manière.",
    ),
  ];
}
