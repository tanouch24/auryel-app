# Matrices confidentialité magasins — Auryel V1

> Établies à partir du **comportement réel de l'application Flutter** (audit
> J1) et des décisions produit V1. Ce que l'application seule ne permet pas
> de confirmer est marqué **« À confirmer après audit backend »** et **ne
> doit pas être déclaré définitivement** sans cette confirmation.
>
> Rappels transverses :
> - **Aucun** SDK d'analytics, de publicité, de suivi publicitaire, de
>   rapport de plantage. Pas de permission `AD_ID`, pas de `firebase_analytics`.
> - **Tracking (au sens ATT) : non observé.** Aucune donnée n'est croisée
>   avec des tiers à des fins publicitaires.
> - **installation_id** : généré et stocké chiffré sur l'appareil, **non
>   transmis** au serveur à ce jour.
> - **Notifications push (FCM)** : **non actives** en V1, aucun jeton
>   collecté.
> - Échanges application ↔ API **chiffrés en transit (HTTPS)** ; l'app
>   refuse le trafic en clair en production (observable côté app).
> - Suppression : possible via l'app (« Supprimer mon compte ») et par
>   e-mail (contact@auryelvoyance.com).

---

# GOOGLE PLAY — DATA SAFETY

## Tableau prêt pour Play Console

| Catégorie | Donnée | Collectée ? | Partagée ? | Oblig. / Fac. | Finalité(s) | Chiffrée en transit | Suppression possible | Remarque / confirmation backend |
|---|---|---|---|---|---|---|---|---|
| Personal info | Adresse e-mail | Oui | Non | Obligatoire | Gestion du compte, authentification, communication de service | Oui | Oui | — |
| Personal info | Nom (prénom) | Oui | Non | Obligatoire (onboarding) | Personnalisation, fonctionnalité de l'app | Oui | Oui | — |
| Personal info | Date de naissance | Oui | Non | Obligatoire (onboarding) | Vérification de l'âge (18+), fonctionnalité de l'app (éléments d'interprétation calculés serveur) | Oui | Oui | Catégorie Play : « Personal info » (pas de sous-catégorie dédiée) |
| Financial info | Historique d'achats / justificatif d'achat (jeton d'achat, identifiant de transaction, identifiant produit) | Oui | Non | Obligatoire (si achat) | Gestion et vérification de l'abonnement, prévention de la fraude | Oui | À confirmer après audit backend (conservation des justificatifs) | Coordonnées bancaires **non** collectées (gérées par Google) |
| Messages | Contenu de consultation (messages envoyés au conseiller + réponses, historique) | Oui | **À confirmer après audit backend** (traitement par un prestataire d'IA) | Facultatif (si l'utilisateur consulte) | Fournir la consultation | Oui (envoi) | À confirmer après audit backend | Ne pas déclarer « partagé » sans confirmation du flux backend → prestataire IA |
| App activity | Tirages (cartes sélectionnées) | Oui | Non | Facultatif | Sauvegarde « parcours », contexte de consultation | Oui | À confirmer après audit backend | — |
| App activity | Progression de la récompense de partage (nombre de jours) | Oui | Non | Facultatif | Suivi de la récompense « X / 30 jours » | Oui | À confirmer après audit backend (cache local supprimé à la suppression de compte) | **Aucun** contenu partagé ni destination transmis |
| App activity | Autres interactions in-app (missions du jour, contenus « aimés », statistiques du Jeu, indicateurs d'intro, panier) | Non (stockées **uniquement sur l'appareil**) | Non | — | Affichage local, confort d'usage | Sans objet (local) | Oui (effacées à la suppression de compte, sauf préférence d'écoute conservée volontairement) | Le Jeu n'accorde aucune récompense |
| App info & performance | Journaux de plantage / diagnostics / performances | Non | Non | — | — | — | — | Aucun SDK de crash/diagnostic |
| Device or other IDs | Identifiant publicitaire (AD_ID) | Non | Non | — | — | — | — | Permission absente |
| Device or other IDs | Identifiant d'installation propriétaire (`installation_id`) | **Non** (non transmis à ce jour) | Non | — | Anti-abus (usage futur) | — | Conservé volontairement sur l'appareil ; disparaît à la désinstallation | À redéclarer si/quand il sera transmis |
| Messages / push | Jeton de notification (FCM) | **Non** (push non actif en V1) | Non | — | — | — | — | À redéclarer lors de l'activation du push |
| User IDs | Identifiant technique de compte (`user_id`) | Oui (reçu du serveur, stocké localement ; **non envoyé** par le client) | Non | Obligatoire | Rattacher l'appareil au bon compte, détecter un changement de compte | Oui | Oui | — |

### Réponses aux questions générales Data Safety

- **Les données sont-elles chiffrées en transit ?** Oui.
- **L'utilisateur peut-il demander la suppression des données ?** Oui
  (suppression du compte dans l'app + e-mail).
- **Collecte auprès d'enfants ?** Non — service **réservé aux 18 ans ou
  plus**.
- **Partage de données ?** Aucun partage à des fins publicitaires. Le seul
  point à trancher est le **traitement du contenu de consultation par un
  prestataire d'IA** : **à confirmer après audit backend** avant de cocher
  « partagé ».

---

# APPLE — APP PRIVACY (DRAFT)

> Pour chaque type : **Oui**, **Non observé**, ou **À confirmer après audit
> backend**. Aucune classification « Sensitive Info » n'est posée
> arbitrairement.

## Data Used to Track You

**Aucune.** Le suivi (tracking) n'est pas observé : pas de SDK publicitaire,
pas d'identifiant publicitaire, aucun partage à des courtiers en données.
→ **App n'utilise pas le tracking.**

## Data Linked to You

| Type Apple | Détail | Statut | Finalité(s) Apple | Remarque |
|---|---|---|---|---|
| Contact Info → Email Address | e-mail de compte | **Oui** | App Functionality | — |
| Contact Info → Name | prénom | **Oui** | App Functionality, Product Personalization | — |
| Health & Fitness | — | **Non observé** | — | Méditation = bien-être, aucune donnée de santé |
| Financial Info → Purchase History | justificatif d'achat, identifiant produit | **Oui** | App Functionality | Pas de coordonnées de paiement (gérées par Apple) |
| Location | — | **Non observé** | — | Aucune permission de localisation |
| Sensitive Info | date de naissance / contenu de tirages / contenu de consultation | **À confirmer** | — | Décision de classification à prendre avec le conseil juridique après audit backend ; ne pas cocher par défaut |
| Contacts | — | **Non observé** | — | Aucun accès au carnet d'adresses ; partage via feuille système |
| User Content → Other User Content | messages de consultation, retour sur le portrait (local), sélection de tirage | **Oui** | App Functionality | Photos / audio produits par l'utilisateur : non |
| Browsing / Search History | — | **Non observé** | — | — |
| Identifiers → User ID | `user_id` technique | **Oui** | App Functionality | — |
| Identifiers → Device ID | IDFA / IDFV | **Non observé** | — | Non collecté |
| Purchases | abonnement / historique d'achat | **Oui** | App Functionality | — |
| Usage Data | product interaction / advertising data | **Non observé** (côté app) | — | Interactions stockées **localement** uniquement ; aucun envoi analytics |
| Diagnostics | crash / performance / other diagnostic | **Non observé** | — | Aucun SDK |
| Other Data | — | **À confirmer** | — | Journalisation serveur (IP, requêtes) : à confirmer après audit backend |

## Data Not Linked to You

- **App activity** liée à la progression de partage : liée au compte → à
  classer dans « Linked ».
- Rien n'est identifié à ce stade comme collecté de façon **non liée** à
  l'utilisateur.

## Éléments « À confirmer après audit backend » (Apple + Google)

1. Le contenu des consultations est-il transmis par le serveur à un
   prestataire d'IA tiers ? Si oui : déclarer « partagé » (Google) et
   préciser la finalité (Apple).
2. Journalisation serveur (adresse IP, requêtes) : type de données, finalité
   (sécurité / prévention fraude), conservation.
3. Périmètre exact des données supprimées par `DELETE /api/app/account`.
4. Prestataire d'e-mails transactionnels éventuel.
