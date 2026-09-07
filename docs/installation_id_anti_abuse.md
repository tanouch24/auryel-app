# Identifiant d'installation — anti-abus « heure gratuite »

## Pourquoi il existe

La première heure de consultation (`3600 s`) est **offerte une seule fois** selon
la politique anti-abus. Sans aucun signal, un même téléphone peut créer plusieurs
comptes (plusieurs emails) et récupérer l'heure gratuite à chaque fois.

`InstallationIdStore` fournit un **signal d'installation** que le backend pourra
utiliser (dans un lot ultérieur) pour reconnaître une même installation qui
recrée des comptes.

## Ce que c'est

- Un identifiant **aléatoire** : 16 octets de `Random.secure()` → **32 caractères
  hexadécimaux minuscules** (128 bits d'entropie). Validé par `^[0-9a-f]{32}$`.
- **Ne dérive d'AUCUN** identifiant matériel ou personnel : ni email, ni
  `user_id`, ni prénom, ni date de naissance, ni modèle/appareil, ni IP, ni MAC,
  ni IMEI, ni `ANDROID_ID`, ni Advertising ID / AAID. Aucun timestamp seul,
  aucun compteur, aucun hash d'email.
- Stocké dans le **stockage chiffré de l'OS** (`FlutterSecureStorage` — Keystore
  Android / Keychain iOS), clé **dédiée** `auryel_installation_id_v1`. Jamais
  dans `SharedPreferences`, jamais dans `TokenStore`.
- **Pas** utilisé pour la publicité. **Pas** utilisé pour du cross-app tracking.
  **Pas** d'analytics. Finalité **unique** : prévention d'abus / fraude sur
  l'heure gratuite.

## Cycle de vie

| Événement | `auryel_installation_id_v1` |
|---|---|
| Premier `getOrCreate()` | généré + persisté (lazy, jamais au Splash) |
| Appels suivants (même installation) | **même valeur** |
| `logout()` | **CONSERVÉ** |
| Changement de compte / `forgetLocalIdentity()` | **CONSERVÉ** |
| Suppression de compte (`DELETE /api/app/account` 2xx) + `LocalUserData.clearPersonal()` | **CONSERVÉ** |
| Désinstallation de l'app | disparaît (comportement normal — aucune tentative de contournement) |

C'est **volontaire** : conserver l'identifiant après une suppression de compte
est ce qui permet de détecter « même installation → nouveau compte → déjà
bénéficiaire de l'heure gratuite ».

## Échec d'écriture du stockage sécurisé

Si `FlutterSecureStorage.write` échoue, `getOrCreate()` renvoie quand même un
identifiant **valide pour la session en cours** (mis en cache mémoire), mais
`SecureInstallationIdStore.isPersisted` vaut `false` et l'identifiant sera
**régénéré au prochain lancement**. **Aucun repli `SharedPreferences`
silencieux** : cette clé ne doit vivre que dans le stockage chiffré.

## Usage réseau — AUJOURD'HUI

**AUCUN.** `installation_id` n'est ajouté à **aucun** payload
(`POST /api/app/auth/register`, `login`, `PATCH /api/app/profile` : **inchangés**).
`AuthController.installationId()` existe comme **seam** : un lot ultérieur le
branchera quand le contrat backend acceptera officiellement le champ.

## L'heure gratuite reste serveur-autoritaire

Le client **n'accorde jamais** de temps gratuit. Il lit et affiche seulement
`quota.first_free_available` / `time.first_free_remaining_seconds` renvoyés par
le serveur. L'identifiant d'installation est un **signal**, pas une décision.

## Data Safety / Politique de confidentialité (à faire)

La future déclaration Google Play **Data Safety** devra lister cet identifiant :
- catégorie : *App activity / other IDs* (identifiant généré par l'app) ;
- finalité : **Fraud prevention, security, and compliance** ;
- non partagé avec des tiers, non utilisé pour la publicité ;
- (pas de permission `AD_ID`, pas de SDK publicitaire).

La politique de confidentialité devra mentionner un identifiant d'installation
aléatoire à des fins de prévention d'abus, conservé pour la durée de
l'installation.
