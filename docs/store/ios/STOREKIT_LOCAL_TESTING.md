# StoreKit local — DEV uniquement

`ios/Runner/Auryel-Local.storekit` contient les deux produits utilisés par
l'application pour les tests Xcode locaux :

- `auryel_premium_monthly` — abonnement auto-renouvelable, 4,99 €, période 1 mois ;
- `auryel_extra_hour` — consommable, 1,99 €.

Ce fichier n'est pas une source de vérité de production et ne remplace pas
App Store Connect. Il ne valide ni les credentials Apple, ni le backend Apple,
ni un achat App Store Sandbox réel.

Pour l'utiliser, ouvrir le workspace iOS dans Xcode, sélectionner le scheme
`Runner`, puis choisir ce fichier dans `Edit Scheme… > Run > Options > StoreKit
Configuration`. Le fichier doit rester limité aux schemes de développement.

Les scénarios réellement couverts par ce mode sont marqués
`STOREKIT_LOCAL_PASS`. Les achats App Store Sandbox, la validation serveur
Apple et les renouvellements Apple réels restent
`REAL_APP_STORE_SANDBOX_REQUIRED`.
