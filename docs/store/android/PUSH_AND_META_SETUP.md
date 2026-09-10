# Auryel Android — Configuration Push (FCM) & Meta App Events

> Aucune valeur secrète ici. Fichiers de config locaux (non versionnés) et noms
> de variables uniquement.

## 1. Firebase / FCM

### Fichiers locaux (non versionnés — voir `.gitignore`)

| Fichier | Rôle |
|---|---|
| `android/app/google-services.json` | Config Firebase Android du projet `auryel-f9e40`, package `com.auryel.auryel`. Fourni hors dépôt. Requis pour tout build (le plugin `com.google.gms.google-services` échoue s'il manque). |

### Gradle

- `android/settings.gradle.kts` : `id("com.google.gms.google-services") version "4.4.3" apply false`
- `android/app/build.gradle.kts` : `id("com.google.gms.google-services")` + core library desugaring (requis par `flutter_local_notifications`).

### AndroidManifest

- `com.google.firebase.messaging.default_notification_channel_id` = `auryel_default`
  (canal créé côté Dart par `LocalNotificationPresenter`, visibilité `PRIVATE`).

### Backend (Railway) — noms de variables

| Variable | Valeur / défaut sûr |
|---|---|
| `FIREBASE_SERVICE_ACCOUNT_JSON` | JSON de la clé de service (Firebase Console → Paramètres → Comptes de service → Générer une clé privée). **Jamais commité.** |
| `FIREBASE_PROJECT_ID` | `auryel-f9e40` |
| `PUSH_ENABLED` | `false` tant que non validé ; `true` pour envoyer réellement |
| `PUSH_DRY_RUN` | `true` (validate_only, aucune livraison) tant que non validé |
| `PUSH_CRON_SECRET` | secret constant-time pour `POST /cron/push-tick` (repli : `DAILY_SECRET`) |
| `PUSH_TIME_MORNING` | `08:30` (pensée du jour, Europe/Paris) |
| `PUSH_TIME_EVENING` | `19:00` (méditation) |
| `PUSH_SLEEP_DAYS` | `wed,sun` |
| `PUSH_SLEEP_TIME` | `22:00` |
| `PUSH_LESSON_DAY` | `sun` |
| `PUSH_LESSON_TIME` | `11:00` |

Défauts si variable absente : `PUSH_ENABLED` faux, dry-run actif, horaires
ci-dessus. Config Firebase absente → `config_error` propre, backend disponible.

### Déclenchement du scheduler

- **PAS** d'APScheduler dans le process web (redémarrages / déploiements /
  sommeil / multi-worker). Le scheduler existant reste sans job push.
- Un **Railway Cron** séparé appelle `POST /cron/push-tick` toutes les 10–15 min
  avec `{"secret": "<PUSH_CRON_SECRET>"}` (ou en-tête `X-Cron-Secret`).
- Idempotence garantie par `notification_sends.dedupe_key`
  (`f"{category}:{user_id}:{période Europe/Paris}"`). Un tick fréquent est sûr.
- Fenêtre de rattrapage : 6 h après l'heure cible (évite une « pensée du jour »
  envoyée tard le soir après une panne).

## 2. Meta App Events (mesure publicitaire, sous consentement)

### Fichiers locaux (non versionnés)

| Fichier | Rôle |
|---|---|
| `~/.auryel_meta_app_id` | App ID Meta (chmod 600) |
| `~/.auryel_meta_client_token` | Client Token Meta (chmod 600) |
| `android/meta.properties` | Généré depuis les deux fichiers ci-dessus : `metaAppId=…` / `metaClientToken=…`. Lu par Gradle (`manifestPlaceholders`). **gitignore.** |

Alternative CI : `-PmetaAppId=… -PmetaClientToken=…` ou
`--dart-define=AURYEL_META_APP_ID=… --dart-define=AURYEL_META_CLIENT_TOKEN=…`.

### Ce qui est désactivé par défaut

- `AutoLogAppEventsEnabled=false` et `AdvertiserIDCollectionEnabled=false` (manifeste).
- Runtime : `setAutoLogAppEventsEnabled(false)`, `setAdvertiserTracking(enabled:false, collectId:false)` tant que pas de consentement.
- **L'identifiant publicitaire GAID n'est jamais collecté** (même après consentement, avec ce plugin).

### Consentement

- `MetaConsentController` — persistance `shared_preferences`
  (`auryel_meta_consent_v1`), **défaut `false`**, jamais pré-coché.
- UI : « Mon compte → Confidentialité → Mesure publicitaire » (`MetaConsentTile`),
  interrupteur révocable.
- Avant consentement : façade `NoopMetaEvents` de fait (aucun événement).
- Après consentement : `setAutoLogAppEventsEnabled(true)` +
  `setAdvertiserTracking(enabled:true, collectId:false)` + activation SDK, puis
  les 4 événements passent.

### Événements (allowlist stricte, aucun paramètre / aucune PII)

| Événement | Déclencheur réel |
|---|---|
| activation / installation | automatique (SDK, sous consentement) |
| `onboarding_completed` | `AuryelState.completeOnboarding()` (1ʳᵉ fois) |
| `paywall_viewed` | ouverture de `PremiumScreen` |
| `subscription_started` | `PurchaseController` — après `verify` serveur 200, **achat neuf uniquement** (jamais restauration / reprise) |
| `consultation_started` | `ConsultationController` — transition « aucune session » → session active au 1ᵉʳ message accepté par le serveur |

### Meta Console — à faire (manuel)

1. App « Auryel Mobile », entreprise vérifiée, package `com.auryel.auryel`,
   activité `com.auryel.auryel.MainActivity`, audience 18+.
2. Plateforme Android : renseigner package + classe + **key hashes** (debug + upload).
3. Récupérer **App ID** + **Client Token** (Paramètres → De base / Avancé).
4. Laisser « Achats / abonnements automatiques » désactivés.
5. Association Google Play : à finaliser APRÈS le premier AAB publiquement
   vérifiable.
6. Data Safety Play : déclarer le partage « Activité dans l'app » vers Meta
   **conditionné au consentement** ; NE PAS cocher « collecte l'identifiant
   publicitaire ».
