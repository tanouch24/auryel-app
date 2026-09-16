# Auryel media catalogs

Les trois catalogues sont indépendants. Le bucket R2 n'est pas listé par
l'application : le backend synchronise un catalogue serveur via un cron
sécurisé et Flutter ne connaît jamais la liste des fichiers.

## ADD MEDITATION

1. Uploader le MP4 dans `meditations/` du bucket vidéo Auryel.
2. Laisser le cron R2 sécurisé déclarer l'objet dans le catalogue serveur.
3. Le backend expose ensuite l'entrée via
   `GET /api/app/content/meditations?media=video`.
4. Vérifier le préfixe, puis lancer les tests ciblés et
   `flutter analyze --no-pub`.

Le lecteur immersif et son chargement lazy sont réutilisés automatiquement.
Les filtres serveur et Flutter refusent tout objet hors de `meditations/*.mp4`.
Une entrée située sous `wake-videos/` ou sous l'ancien préfixe
`meditation-videos/` est invalide pour ce catalogue.

## ADD WAKE VIDEO

1. Uploader le MP4 dans `wake-videos/`.
2. Déclarer la ressource dans `lib/data/wake_video.dart` avec son identifiant
   et son URL/objet réel.
3. La conserver dans les écrans et le cache du Réveil : ne pas l'ajouter à
   `MeditationVideoCatalog`.
4. Vérifier configuration, déclenchement, Stop, Snooze et fallback du Réveil.

## ADD EBOOK

1. Uploader le PDF sous `ebooks/` et sa couverture dans le stockage ebook.
2. Déclarer le livre dans le catalogue serveur consommé par
   `WellbeingEbooksController` (`/api/app/wellbeing/ebooks`).
3. Renseigner au minimum PDF, titre et état actif; compléter couverture,
   sous-titre, description, catégorie, durée et ordre si connus.
4. Vérifier `EbookReaderScreen`/`pdfrx`, ainsi que les états vide, chargement
   et erreur.

## Règles communes

- Ne jamais rendre le bucket listable publiquement pour alimenter l'UI.
- Un upload et sa déclaration dans son catalogue sont nécessaires.
- Ne jamais mélanger `ebooks/`, `meditations/` et `wake-videos/`.
- Ne pas ajouter de faux fichier, thumbnail ou métadonnée.
