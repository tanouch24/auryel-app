# Auryel — Dossier de dépôt Google Play (Android)

> État : PRÉPARATION. Ce document est la source de vérité pour la fiche Play et
> la piste de test fermée. Aucune valeur secrète n'y figure. À relire avec un
> conseil juridique avant toute soumission.

---

## 1. Identité de l'application

| Champ | Valeur |
|---|---|
| Nom de l'application | **Auryel** |
| Nom du package | `com.auryel.auryel` |
| Activité principale | `com.auryel.auryel.MainActivity` |
| Éditeur | 3E Technology Ltd — company number 17179077 — 71-75 Shelton Street, Covent Garden, London WC2H 9JQ, Royaume-Uni |
| Contact | contact@auryelvoyance.com |
| Domaine | auryelvoyance.com |
| Public cible | **18 ans et plus** (adultes uniquement) |
| Catégorie recommandée | **Style de vie** (Lifestyle). Alternative : « Bien-être » si disponible dans la taxonomie du compte. |
| Tags (jusqu'à 5) | bien-être · méditation · développement personnel · tarot · journal |

### 2. Description courte (≤ 80 caractères)

> Un compagnon quotidien : pensée du jour, méditation, tirage et un conseiller à l'écoute.

### 3. Description complète (≤ 4000 caractères) — proposition

> **Auryel, votre rituel quotidien de recentrage.**
>
> Auryel réunit dans une seule application une pratique douce et régulière :
> une pensée du jour à méditer, une séance audio pour ralentir, un tirage de
> trois cartes pour prendre du recul, et un conseiller avec qui échanger quand
> vous en ressentez le besoin.
>
> **Chaque jour, gratuitement :**
> • La pensée du jour et son explication
> • Une méditation guidée « Ton Moment »
> • Un tirage de trois cartes à interpréter et à sauvegarder
> • Votre humeur du jour et votre parcours (contenus sauvegardés, progression)
> • Le partage d'une carte inspirante avec vos proches
>
> **Avec l'abonnement Premium :**
> • 8 heures de consultation par mois avec le conseiller de votre choix
> • Un fil de conversation continu, qui garde le contexte
> • Messages illimités pendant votre temps de consultation
>
> **Notre engagement :** un prix clair, pas de publicité dans l'application,
> pas de compteur à la minute, pas de relances abusives. Vous activez les
> notifications si vous le souhaitez, et la mesure publicitaire n'est jamais
> active sans votre accord explicite.
>
> Une partie des échanges est gérée par une intelligence artificielle, avec un
> encadrement humain. Auryel est un service de divertissement et de bien-être :
> il ne remplace pas un avis médical, psychologique, juridique ou financier, et
> ne promet aucun résultat. Réservé aux personnes majeures.

*(Positionnement : bien-être / compagnon quotidien / pratique quotidienne /
méditation / réflexion personnelle / relation avec un conseiller. NE PAS
présenter la fiche comme un mur de tarot/voyance. NE PAS employer « coaching ».)*

---

## 4. URLs de la fiche

| Champ | URL |
|---|---|
| Site web | https://auryelvoyance.com |
| Politique de confidentialité | https://auryelvoyance.com/confidentialite |
| Conditions d'utilisation | https://auryelvoyance.com/cgu |
| Conditions de vente | https://auryelvoyance.com/cgv |
| Suppression de compte (obligatoire Play) | https://auryelvoyance.com/suppression-compte |
| Email d'assistance | contact@auryelvoyance.com |

> ⚠️ Les pages légales ont été mises à jour dans ce lot (FCM, Meta sous
> consentement, 7,99 €/8 h, identifiants d'appareil, historique d'achat, retrait
> du terme « DPO », retrait des mentions WhatsApp/Stripe legacy). **Elles ne
> sont pas encore déployées** — cf. rapport, section Juridique.

---

## 5. Fonctionnement de l'IA (à coller dans « Notes pour l'examinateur »)

- Le cœur conversationnel d'Auryel s'appuie sur des modèles de langage
  (OpenAI, avec repli Groq selon configuration). Certains messages sont
  reformulés ou supervisés par un humain.
- Les messages vocaux de présentation des conseillers sont produits par une
  voix de synthèse.
- L'application affiche une mention de transparence : « Une partie de nos
  échanges est gérée par une intelligence artificielle. »
- Garde-fous : détection de détresse / automutilation / violence / mineurs ;
  jamais de promesse de résultat ; ne se fait jamais passer pour un humain
  certifié ; bouton « Signaler cette réponse » côté app.

## 6. Abonnement (à coller dans « Notes pour l'examinateur »)

- Produit : `auryel_premium_monthly` — abonnement auto-renouvelable mensuel,
  prix de référence **7,99 €/mois** (le prix effectif est celui du Store selon
  la région).
- Contrepartie : **8 heures (28 800 secondes) de temps de consultation par
  période de facturation**. Portefeuille de temps, pas un nombre fixe de
  sessions ; messages illimités pendant le temps disponible.
- Le décompte du temps est **autoritaire côté serveur**. Le Store gère l'achat
  et le renouvellement ; le backend Auryel gère le temps consommé.
- Première heure offerte : 1 crédit unique par compte, à l'inscription (pas un
  produit payant).
- Restauration : « Restaurer mes achats » dans l'écran Premium (après
  changement d'appareil / réinstallation).
- Résiliation : depuis Google Play → Abonnements. L'app fournit un raccourci
  « Gérer mon abonnement » qui ouvre la page officielle ; l'app ne résilie
  jamais à la place de l'utilisateur. Droits jusqu'à la fin de la période payée.
- Dépassement payant (2,90 €) : **hors périmètre V1**, non configuré comme
  produit Store, non proposé dans l'app.

### 6 bis. Règle exacte des 28 800 secondes

- Une ligne `consultation_allowance` par **période d'abonnement réelle**
  (`PRIMARY KEY (user_id, period_start)`), `monthly_allowance_seconds = 28800`.
- Création idempotente : `INSERT ... ON CONFLICT (user_id, period_start) DO
  NOTHING`. Un `restore`, un redémarrage, une double notification Play ou une
  re-vérification ne recréditent jamais la même période.
- `sync_allowance` détecte le `same_cycle` (même abonnement + même
  `current_period_start`) et n'aligne rien de plus.
- Annuler puis se réabonner ouvre une **nouvelle** `period_start` -> nouvelle
  allocation (comportement voulu : nouvelle période payée). Reprendre le même
  cycle -> même `period_start` -> aucun re-crédit.
- Les récompenses (partage +1 h, bien-être +15 min, Memory +5/+10/+15 min)
  atterrissent dans `accounts.purchased_seconds_remaining`, bucket **jamais
  remis à zéro** par le renouvellement, consommé en dernier. Elles ne sont pas
  perdues au renouvellement.

### 6 ter. Comportement à solde zéro

- `GET /api/consultation/state` renvoie le bloc `time` : total disponible,
  `monthly_used_seconds`, et la date de renouvellement si connue.
- À zéro : aucune nouvelle consommation Premium possible (le serveur refuse en
  402 `time_exhausted`). Le contenu gratuit reste accessible.
- L'app affiche « crédit mensuel épuisé » + la prochaine date de renouvellement
  quand elle est disponible, et propose l'écran Premium (jamais un mur « PAYE »).

---

## 7. Data Safety (formulaire Play) — d'après la version finale

### Données collectées et transmises

| Type | Collecté | Partagé | Finalité | Obligatoire |
|---|---|---|---|---|
| Adresse e-mail | Oui | Non | Compte, connexion, communications de service | Oui |
| Prénom (facultatif) | Oui | Non | Personnalisation | Non |
| Date de naissance | Oui | Non | Éléments d'interprétation (calcul serveur) | Non |
| ID utilisateur (compte) | Oui | Non | Fonctionnement du compte | Oui |
| Historique d'achat | Oui | Non | Vérification d'abonnement, gestion du temps | Oui |
| Messages in-app (consultations) | Oui | Non | Fourniture de la consultation | Non |
| Contenu généré par l'utilisateur (tirages) | Oui | Non | Sauvegarde « Mon parcours » | Non |
| Jeton de notification (device ID / « autres identifiants ») | Oui (si notifications activées) | Non | Notifications push | Non |
| Infos sur l'appareil (plateforme, version OS/app) | Oui | Non | Compatibilité, support, notifications | Non |
| Journaux techniques / diagnostics | Oui | Non | Stabilité, sécurité, prévention de la fraude | Non |
| Activité dans l'app (événements de mesure) | **Oui, uniquement avec consentement** | **Oui, à Meta, uniquement avec consentement** | **Publicité / mesure de performance** | Non |
| Adresse IP | Collectée sous forme tronquée/hachée | Non | Sécurité, limitation de débit | — |

### Déclarations spécifiques

- **Identifiant publicitaire (Advertising ID)** : **NON collecté.** Le SDK Meta
  est configuré `AdvertiserIDCollectionEnabled=false` (manifeste) et
  `setAdvertiserTracking(collectId:false)` (runtime). Ne PAS cocher « collecte
  l'identifiant publicitaire ». (Si une version future l'active : re-déclarer +
  ajouter la permission `com.google.android.gms.permission.AD_ID` + ré-auditer.)
- **Publicités** : l'application **n'affiche aucune publicité**. Elle réalise
  une **mesure publicitaire** (attribution d'installation/conversion via Meta)
  **uniquement après consentement explicite de l'utilisateur**, révocable dans
  « Mon compte ». Déclarer le partage « Activité dans l'app » vers un tiers à
  des fins publicitaires, conditionné au consentement.
- **Chiffrement en transit** : Oui (HTTPS ; l'app refuse le clair en release).
- **Suppression des données** : Oui — in-app (« Mon compte → Supprimer mon
  compte ») et par e-mail. URL : https://auryelvoyance.com/suppression-compte
- **Données de santé** : Aucune.
- **Familles / enfants** : application **18+**, ne cible pas les enfants.

---

## 8. Classification du contenu (questionnaire IARC)

- Public : adultes (18+).
- Thèmes : références à la voyance / tarot / ésotérisme (divertissement).
  Aucune violence, aucun contenu sexuel, aucun langage grossier gratuit,
  aucun contenu de jeu d'argent réel (le « Jeu Auryel » est un memory sans
  mise ni gain monétaire ; ses bonus sont du temps de consultation non
  convertible en argent).
- Interactions : échange textuel avec un conseiller (contenu généré par IA +
  supervision humaine). Pas d'UGC public, pas de mise en relation entre
  utilisateurs, pas de chat entre inconnus.
- Achats numériques : Oui (abonnement).
- Classification attendue : « PEGI 12 / Teen » à « PEGI 16 » selon le
  questionnaire ; distribution restreinte 18+ via le paramètre d'audience.

---

## 9. Pays / distribution

- Lancement initial recommandé : **France** (marché cible, langue FR unique).
- Extension ultérieure : Belgique, Suisse, Luxembourg, Canada (Québec) —
  après validation du contenu et de la fiscalité.
- Exclure les pays où la voyance/ésotérisme est réglementé restrictivement si
  le conseil juridique le recommande.

---

## 10. Captures d'écran requises (à produire depuis l'app RÉELLE finalisée)

Ordre imposé (montrer la LARGEUR de l'expérience, tarot en dernier) :

1. **Accueil / pensée du jour** — portrait du conseiller, phrase du jour, humeur.
2. **Conseiller / consultation** — écran de conversation (bulles, voix du
   conseiller), statut « consultation ouverte ».
3. **Méditation** — lecteur audio « Ton Moment ».
4. **Parcours / récompenses** — « Mon parcours », progression partage/bien-être.
5. **Tirage** — éventail de 3 cartes + interprétation.

Formats Play :
- Captures téléphone : 2 à 8, PNG/JPEG, ratio 16:9 ou 9:16, côté min 320 px,
  côté max 3840 px.
- Icône haute résolution : **512 × 512** PNG 32 bits (avec alpha).
- Image de mise en avant (feature graphic) : **1024 × 500** PNG/JPEG.
- (Tablette 7"/10" : facultatif tant que l'app n'est pas optimisée tablette.)

**⚠️ Aucune capture ne doit être fabriquée / maquettée.** Elles proviennent de
builds installées, avec des données réalistes.

### Assets — état

| Asset | État | Action |
|---|---|---|
| Icône 512×512 | À vérifier (mipmap `ic_launcher` présent, source 512 à confirmer) | Fournir le PNG 512×512 définitif |
| Feature graphic 1024×500 | **MANQUANT** | À produire (design final, pas de maquette) |
| Captures téléphone ×5 | **MANQUANTES** | À capturer sur l'app finalisée (Samsung SM-A075F ou équivalent) |
| Vidéo promo (facultative) | Absente | Optionnel |

---

## 11. Compte examinateur / procédure de test (sans secret)

- Fournir à l'examinateur un **compte de test dédié** (e-mail + mot de passe)
  créé via le parcours normal d'inscription. Ne PAS mettre l'e-mail/mot de
  passe dans ce fichier versionné : les transmettre dans le champ « Identifiants
  de connexion » de la console Play.
- Pré-créditer ce compte : 1 abonnement de test actif (licence de test Play) +
  éventuellement un crédit de temps via l'outil support.
- Étapes de test à décrire :
  1. Ouvrir l'app → onboarding (conseiller, prénom, date de naissance,
     portrait) → créer le compte.
  2. Accueil : consulter la pensée du jour, lancer une méditation, faire un
     tirage.
  3. Activer les notifications via « Mon compte → Notifications » (CTA
     explicite ; jamais demandé au démarrage).
  4. Ouvrir une consultation : envoyer un message → la session démarre, le
     temps se décompte côté serveur.
  5. Écran Premium : voir l'offre 7,99 €/8 h ; « Restaurer mes achats ».
  6. « Mon compte → Confidentialité » : activer/désactiver la mesure
     publicitaire (non pré-cochée).
  7. « Mon compte → Supprimer mon compte » : suppression réelle + retour login.

---

## 12. Checklists

### 12.1 Accès à la production (Play Console)

- [ ] Compte Play Console vérifié (identité + société), frais 25 $ réglés.
- [ ] Application créée, package `com.auryel.auryel`.
- [ ] Fiche principale complète (nom, descriptions, captures, icône, feature graphic).
- [ ] Politique de confidentialité en ligne (URL live) + pages CGU/CGV/suppression.
- [ ] Data Safety renseigné selon §7 (dont mesure Meta conditionnée au consentement, GAID non collecté).
- [ ] Classification du contenu (IARC) complétée.
- [ ] Public cible = 18+ ; « Contient des annonces » = **NON**.
- [ ] Coordonnées développeur (adresse société, e-mail, téléphone) à jour.
- [ ] Pays de distribution sélectionnés (France d'abord).
- [ ] Produit d'abonnement `auryel_premium_monthly` créé, base plan 7,99 €/mois, actif.
- [ ] Testeurs de licence ajoutés (comptes Google autorisés aux achats de test).
- [ ] Service account Google Cloud lié au projet Play + API Android Publisher activée + `GOOGLE_SERVICE_ACCOUNT_JSON` / `GOOGLE_PLAY_PACKAGE_NAME` posés sur Railway (vérification serveur des achats).
- [ ] Empreintes SHA (clé d'upload + éventuelle clé App Signing Google) enregistrées dans Firebase (`auryel-f9e40`) et dans la console Meta (key hashes).
- [ ] Notes pour l'examinateur rédigées (§5, §6, §11).

### 12.2 Fin de test fermé

- [ ] Piste de test fermée créée, ≥ 12 testeurs, ≥ 14 jours d'activité continue (exigence Play pour les nouveaux comptes développeurs particuliers ; vérifier si applicable au compte société).
- [ ] Achat d'abonnement testé de bout en bout (build installée PAR Play) : achat → verify serveur 200 → 28 800 s crédités une seule fois.
- [ ] Restauration testée sur un 2ᵉ appareil / après réinstallation.
- [ ] Renouvellement testé (abonnement de test à renouvellement accéléré) : pas de double crédit.
- [ ] Annulation testée : accès jusqu'à fin de période, pas de re-crédit à la reprise.
- [ ] Notifications push testées : foreground / background / app tuée / tap → bon onglet / texte générique sur écran verrouillé.
- [ ] Suppression de compte testée : purge serveur (dont `push_devices`) + retour login.
- [ ] Retours testeurs traités ; aucun crash bloquant (crash-free ≥ 99 %).

### 12.3 Release production

- [ ] `versionCode` strictement supérieur à 2 (le dernier AAB publié = 2). Ne PAS l'incrémenter avant l'AAB final.
- [ ] `versionName` défini (ex. `1.0.0`).
- [ ] AAB release signé avec la clé d'upload Auryel (`android/key.properties` présent).
- [ ] `--dart-define=AURYEL_API_BASE_URL=https://<prod>` fourni au build release (sinon échec voulu).
- [ ] `--dart-define=AURYEL_META_APP_ID` / `AURYEL_META_CLIENT_TOKEN` fournis (ou `android/meta.properties` présent) — sinon SDK Meta inactif (dégradation propre).
- [ ] `google-services.json` présent localement (jamais commité).
- [ ] R8/minification vérifiée sur l'AAB release (pas de crash au lancement).
- [ ] Data Safety re-vérifié si un SDK a changé de version.

### 12.4 Plan de déploiement progressif

1. Test interne (équipe) — build de validation, smoke test.
2. Test fermé (12+ testeurs, 14 j) — parcours complet + achats de test.
3. Test ouvert (optionnel, 50–200 testeurs) — 3 à 7 jours.
4. Production **déploiement échelonné** : 5 % → 10 % → 20 % → 50 % → 100 %,
   24–48 h par palier, en surveillant crash-free, ANR, avis, taux de conversion
   paywall et taux d'échec `verify`.
5. Halte immédiate + correctif si crash-free < 98 % ou pic d'échecs de
   vérification d'achat.

---

## 13. Variables Railway nécessaires (noms uniquement)

Déjà en place (backend) : `DATABASE_URL`, `DAILY_SECRET`,
`GOOGLE_SERVICE_ACCOUNT_JSON`, `GOOGLE_PLAY_PACKAGE_NAME`,
`FIREBASE_SERVICE_ACCOUNT_JSON`, `FIREBASE_PROJECT_ID`, `PUSH_ENABLED`,
`PUSH_DRY_RUN`.

À ajouter avant l'activation réelle du push programmé :
`PUSH_CRON_SECRET` (ou réutiliser `DAILY_SECRET`), `PUSH_TIME_MORNING`,
`PUSH_TIME_EVENING`, `PUSH_SLEEP_DAYS`, `PUSH_SLEEP_TIME`, `PUSH_LESSON_DAY`,
`PUSH_LESSON_TIME`. Défauts sûrs si absents : `PUSH_ENABLED` faux, dry-run
actif, horaires 08:30 / 19:00 / mer+dim 22:00 / dim 11:00 (Europe/Paris).

---

## 14. Éléments nécessaires pour finir la piste de test (bloquants)

1. **Produit `auryel_premium_monthly` créé et actif dans Play Console** (base
   plan 7,99 €/mois). Sans lui : pas d'achat testable, l'app affiche l'offre
   « indisponible » proprement (aucun repli test).
2. **Service account Play + API Android Publisher** liés, clés posées sur
   Railway (`GOOGLE_SERVICE_ACCOUNT_JSON`, `GOOGLE_PLAY_PACKAGE_NAME`).
3. **Backend déployé** avec ce lot (migration v40 `push_devices` /
   `notification_sends`, endpoints `/api/app/push/*`, `/cron/push-tick`).
4. **`FIREBASE_SERVICE_ACCOUNT_JSON`** posée sur Railway (déjà indiqué comme
   présent) pour l'envoi FCM réel ; passer `PUSH_ENABLED=true` /
   `PUSH_DRY_RUN=false` seulement après validation en dry-run.
5. **Railway Cron** externe appelant `POST /cron/push-tick` (toutes les 10–15
   min) avec le secret constant-time.
6. **Firebase Console** : clé de service FCM générée, SHA (debug + upload)
   ajoutés.
7. **Meta Console** : plateforme Android ajoutée (package + activité + key
   hashes), App ID + Client Token récupérés (déjà en local :
   `~/.auryel_meta_app_id`, `~/.auryel_meta_client_token` → `android/meta.properties`).
8. **Assets** : feature graphic 1024×500, 5 captures réelles, icône 512×512
   définitive.
9. **Déploiement des pages légales mises à jour** (Netlify) après relecture
   juridique.
10. **AAB release final** signé + `versionCode` > 2 + tous les `--dart-define`
    de production.
