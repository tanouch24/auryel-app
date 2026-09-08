# Checklist de soumission aux magasins — Auryel V1

> Éléments **actionnables** uniquement. `[ ]` = à faire, `[x]` = fait et
> vérifié dans le dépôt à ce jour (lot J3).

---

## LEGAL — APPLICATION

- [x] Âge minimum 18+ appliqué à l'onboarding, à la création de compte et à
  l'édition de la date de naissance (lot J2).
- [x] Wording IA canonique affiché et inchangé :
  « Une partie de nos échanges est gérée par une intelligence artificielle. »
- [x] Disclaimer voyance/tarot/guidance accessible dans
  « Mon compte → Informations & confidentialité ».
- [x] Note « les réponses peuvent être générées ou assistées par une IA…
  inexactes ou incomplètes » accessible au même endroit.
- [x] Informations éditeur visibles dans l'app (Auryel · 3E Technology Ltd ·
  company number 17179077 · adresse · contact@auryelvoyance.com).
- [x] Politique de confidentialité lisible **dans l'app** (vue locale).
- [x] Conditions générales d'utilisation lisibles **dans l'app** (vue locale).
- [x] Conditions Premium lisibles **dans l'app** (vue locale).
- [x] Mentions légales lisibles **dans l'app** (vue locale).
- [x] Plus aucun « Bientôt disponible » pour les 3 documents juridiques
  principaux (confidentialité, CGU, mentions légales).
- [x] Suppression de compte accessible et fonctionnelle dans l'app.
- [ ] Relecture juridique finale des 4 textes (confidentialité, CGU,
  Premium, mentions légales).

## LEGAL — WEB (mini-lot site suivant, hors périmètre J3)

- [ ] Publier `https://auryelvoyance.com/confidentialite`
- [ ] Publier `https://auryelvoyance.com/cgu`
- [ ] Publier `https://auryelvoyance.com/mentions-legales`
- [ ] Publier `https://auryelvoyance.com/suppression-compte`
  (source : `docs/legal/account_deletion_page_fr.md`)
- [ ] Une fois les URLs en ligne : renseigner `LegalLinks` (Dart) et, si
  souhaité, doubler les vues locales d'un lien externe.

## GOOGLE PLAY

- [ ] Renseigner l'URL publique de politique de confidentialité dans la
  fiche Play (bloquant tant que l'URL web n'est pas publiée).
- [ ] Compléter le formulaire **Data Safety** à partir de
  `store_privacy_matrix.md` (section Google Play).
- [ ] Trancher la ligne « contenu de consultation → prestataire IA »
  (partagé ou non) après audit backend.
- [ ] Content rating : renseigner le questionnaire (thème voyance / tarot ;
  public adulte 18+).
- [ ] Vérifier l'absence de permission `AD_ID` dans le manifeste fusionné
  (déjà confirmé au lot Android).
- [ ] Fiche Store : nom, description, captures d'écran (mettre en avant la
  largeur de l'expérience, pas uniquement le tarot).
- [ ] Lien « Suppression de compte » exigé par Play : pointer vers la page
  web `/suppression-compte` une fois publiée.

## APPLE

- [ ] Renseigner l'URL publique de politique de confidentialité dans App
  Store Connect.
- [ ] Compléter **App Privacy** à partir de `store_privacy_matrix.md`
  (section Apple).
- [ ] Décider de la classification « Sensitive Info » (date de naissance /
  tirages / consultations) avec le conseil juridique.
- [ ] Confirmer « App does not use tracking ».
- [ ] Préparer la « Notes for Review » (positionnement bien-être /
  guidance ; réponse anticipée à la règle 4.3(b)).
- [ ] Vérifier la présence de « Sign in with Apple » si un jour un login
  social est ajouté (aucun login social en V1 → non requis).

## CONFIRMATIONS BACKEND (bloquant pour la publication des textes)

- [ ] Prestataire(s) d'IA : identité, rôle, catégories de données reçues.
- [ ] Conservation des données chez le prestataire d'IA ; entraînement ou
  non ; localisation.
- [ ] Durées de conservation backend : compte, profil, messages de
  consultation, tirages, justificatifs d'achat, journaux.
- [ ] Périmètre exact de `DELETE /api/app/account`.
- [ ] Journalisation serveur (IP, requêtes) : finalités, durées.
- [ ] Hébergeur : identité, adresse, pays (mentions légales).
- [ ] Prestataire d'e-mails transactionnels éventuel.
- [ ] Transferts internationaux : pays et garanties par prestataire.

## FIREBASE / PUSH (lot suivant, hors périmètre J3)

- [ ] Ajouter `google-services.json` + plugin Google Services.
- [ ] Mettre à jour la Politique de confidentialité et les matrices magasins
  (jeton FCM, Firebase Installations ID).

## ASSETS MÉDITATION

- [ ] Fournir les fichiers audio `assets/meditations/*` (5 séances) et les
  déclarer dans `pubspec.yaml` (actuellement absents ; l'écran dégrade
  proprement).

## QA FINALE

- [ ] Parcours complet 18+ : refus propre pour une date < 18 ans.
- [ ] Ouverture de chaque document juridique dans l'app sans erreur.
- [ ] Aucun achat déclenché en naviguant dans les écrans juridiques.
- [ ] Restauration d'achat testée sur un second appareil.
- [ ] Suppression de compte testée (succès, échec réseau, 401).

## BUILD

- [ ] Fixer `version` dans `pubspec.yaml` (versionName + versionCode) avant
  le build final ; ne pas dépendre de `local.properties`.
- [ ] Build release avec `--dart-define=AURYEL_API_BASE_URL=https://…`.
- [ ] Sauvegarde de la clé d'upload (`key.properties` + keystore) vérifiée.
- [ ] Minify / shrink laissés désactivés pour la V1.
