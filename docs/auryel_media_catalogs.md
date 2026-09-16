# Auryel media catalogs

Les trois catalogues sont indépendants. Le bucket R2 n'est pas listé par
l'application et aucun fichier n'est découvert automatiquement par son
extension `.mp4`.

## ADD MEDITATION

1. Uploader le MP4 dans `meditation-videos/` du bucket vidéo Auryel.
2. Ajouter une entrée dans `MeditationVideoCatalog.entries` dans
   `lib/data/meditation_video_catalog.dart`.
3. Renseigner au minimum `id`, `title`, `objectKey`, `url`, `sortOrder` et
   `isActive`; compléter `duration`, `category`, `thumbnailUrl` et les tags si
   ces métadonnées existent réellement.
4. Vérifier le préfixe, puis lancer les tests ciblés et
   `flutter analyze --no-pub`.

Le lecteur immersif et son chargement lazy sont réutilisés automatiquement.
Une entrée située sous `wake-videos/` est invalide pour ce catalogue.

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
- Ne jamais mélanger `ebooks/`, `meditation-videos/` et `wake-videos/`.
- Ne pas ajouter de faux fichier, thumbnail ou métadonnée.
