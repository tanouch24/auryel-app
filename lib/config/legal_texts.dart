/// Textes juridiques et d'identité affichés DANS l'application (lot J3).
///
/// SOURCE UNIQUE. Ces constantes alimentent :
///  - le bloc « Informations & confidentialité » du Dashboard ;
///  - l'écran de lecture [LegalDocumentScreen] (versions condensées mais
///    complètes des essentiels — la version longue vit dans `docs/legal/*` et
///    sera publiée sur auryelvoyance.com par un mini-lot site) ;
///  - l'écran Premium (accès aux Conditions Premium et à la Politique de
///    confidentialité).
///
/// AUCUNE URL n'est déclarée ici comme ouvrable : l'adresse du site est citée
/// comme texte informatif. Les liens web actifs seront branchés dans
/// `LegalLinks` quand les pages seront réellement en ligne.
///
/// Le wording IA canonique (« Une partie de nos échanges est gérée par une
/// intelligence artificielle. ») reste défini dans `ai_transparency_note.dart`
/// et n'est pas dupliqué ici.
library;

// --------------------------------------------------------------------------
// Identité de l'éditeur (informations connues et confirmées).
// --------------------------------------------------------------------------

const String kServiceName = 'Auryel';
const String kPublisherName = '3E Technology Ltd';
const String kPublisherLegalForm = 'Private Limited Company';
const String kCompanyNumber = '17179077';
const String kPublisherIncorporationDate = '24 April 2026';
const String kPublisherAddress =
    '71-75 Shelton Street, Covent Garden, London, United Kingdom, WC2H 9JQ';
const String kSupportEmail = 'contact@auryelvoyance.com';
const String kWebsiteUrl = 'https://auryelvoyance.com';

/// Résumé d'identité affiché dans « Informations & confidentialité ».
const String kPublisherIdentitySummary =
    '$kServiceName est édité par $kPublisherName '
    '($kPublisherLegalForm), company number $kCompanyNumber.\n'
    '$kPublisherAddress\n'
    'Contact : $kSupportEmail — $kWebsiteUrl';

// --------------------------------------------------------------------------
// Disclaimers courts (à afficher dans « Informations & confidentialité »,
// jamais à chaque message de consultation).
// --------------------------------------------------------------------------

/// Disclaimer produit — wording canonique J3, ne pas paraphraser sans
/// validation juridique.
const String kAuryelDisclaimerText =
    'Les contenus de voyance, tarot et guidance proposés par Auryel sont '
    'fournis à titre indicatif et de divertissement. Ils ne garantissent '
    'aucun événement ou résultat futur et ne remplacent pas l’avis d’un '
    'professionnel de santé, psychologue ou psychiatre, avocat, conseiller '
    'financier ou tout autre professionnel qualifié.';

/// Note IA complémentaire — wording canonique J3.
const String kAiResponsesDisclaimerText =
    'Les réponses proposées par Auryel peuvent être générées ou assistées '
    'par des systèmes d’intelligence artificielle. Elles peuvent être '
    'inexactes ou incomplètes.';

// --------------------------------------------------------------------------
// Versions IN-APP condensées des documents juridiques.
// Convention de rendu ([LegalDocumentScreen]) : une ligne entièrement en
// capitales = titre de section ; ligne vide = respiration ; sinon paragraphe.
// --------------------------------------------------------------------------

const String kLegalNoticeInAppText = '''
ÉDITEUR

Auryel est édité par 3E Technology Ltd, Private Limited Company de droit
anglais et gallois, company number 17179077, incorporée le 24 April 2026.

Siège social : 71-75 Shelton Street, Covent Garden, London, United Kingdom,
WC2H 9JQ.

CONTACT

E-mail : contact@auryelvoyance.com
Site : auryelvoyance.com

HÉBERGEMENT

L'identité de l'hébergeur de l'infrastructure du service sera précisée dans
la version publiée sur auryelvoyance.com.

ÂGE

Auryel est réservé aux personnes âgées de 18 ans ou plus.
''';

const String kPrivacyPolicyInAppText = '''
RESPONSABLE DU TRAITEMENT

3E Technology Ltd (company number 17179077), 71-75 Shelton Street, Covent
Garden, London, United Kingdom, WC2H 9JQ. Contact : contact@auryelvoyance.com.
Aucun délégué à la protection des données n'a été désigné ; l'adresse
ci-dessus est un point de contact.

PUBLIC

Auryel est réservé aux personnes âgées de 18 ans ou plus et ne collecte pas
sciemment les données de mineurs.

DONNÉES TRAITÉES

Compte : adresse e-mail, mot de passe (transmis pour l'authentification,
jamais conservé en clair par l'application), identifiant technique de compte.
Profil : prénom, date de naissance, conseiller choisi ; à partir de la date
de naissance, des éléments d'interprétation sont calculés côté serveur.
Consultations : messages échangés avec le conseiller et historique de la
consultation en cours.
Tirages : cartes sélectionnées et interprétations enregistrées.
Abonnement : statut d'abonnement et justificatif d'achat transmis par le
magasin (jeton d'achat ou identifiant de transaction). Aucune coordonnée
bancaire n'est collectée par Auryel.
Récompense de partage : nombre de jours de partage déclarés. Le contenu
partagé et la destination ne sont pas transmis.
Données techniques : données de connexion nécessaires au fonctionnement de
l'API.

DONNÉES RESTANT SUR L'APPAREIL

Instantané d'onboarding (prénom, date de naissance, conseiller, texte de
portrait généré localement et retour associé), suivis locaux (missions,
contenus aimés, statistiques du Jeu, indicateurs d'intro, panier),
préférence d'écoute, choix de consentement à la mesure publicitaire. Un
identifiant d'installation aléatoire est stocké de façon chiffrée sur
l'appareil ; il n'est pas transmis au serveur à ce jour.

NOTIFICATIONS PUSH

Si vous les activez, un jeton d'enregistrement de notification (Firebase
Cloud Messaging, fourni par Google) rattaché à votre appareil est transmis
au serveur avec la plateforme et la version de l'application, afin
d'acheminer des rappels doux et les messages de votre conseiller. Le contenu
affiché reste générique (rien de sensible sur l'écran verrouillé). Le jeton
est supprimé à la déconnexion de l'appareil, à la suppression du compte ou
dès qu'il devient invalide. Les notifications sont désactivables à tout
moment dans les réglages du téléphone.

MESURE PUBLICITAIRE (FACULTATIVE, AVEC CONSENTEMENT)

Par défaut, aucune mesure publicitaire n'est active. Si — et seulement si —
vous activez la « mesure publicitaire » dans « Mon compte », des événements
non nominatifs (installation, ouverture de l'offre, abonnement démarré,
consultation démarrée) sont transmis à Meta Platforms, Inc. à des fins
d'attribution de campagne. Aucun message, contenu de consultation, tirage,
e-mail, téléphone, nom, prénom, date de naissance ni identifiant interne
n'est transmis. L'identifiant publicitaire de l'appareil n'est pas collecté.
Ce consentement n'est pas pré-coché et reste révocable à tout moment.

CE QUE L'APPLICATION NE FAIT PAS

Aucune donnée de localisation, de contacts, de photos, de micro ou de
caméra. Aucun rapport de plantage tiers. Aucune publicité affichée dans
l'application. Aucune mesure publicitaire sans votre consentement explicite.

INTELLIGENCE ARTIFICIELLE

Une partie de nos échanges est gérée par une intelligence artificielle, avec
un encadrement humain ; certains messages vocaux sont produits par une voix
de synthèse. Les traitements peuvent faire intervenir des prestataires
technologiques spécialisés (notamment OpenAI, et selon la configuration
Groq) agissant pour la fourniture du service. Les réponses peuvent être
inexactes ou incomplètes et ne constituent pas un avis médical,
thérapeutique, psychologique, juridique ou financier.

FINALITÉS ET BASES JURIDIQUES

Fournir le compte, les consultations, les tirages, les contenus et
l'abonnement (exécution du contrat) ; respecter des obligations légales
(notamment comptables et fiscales) ; assurer la sécurité et prévenir la
fraude et les abus, et améliorer le service dans la stricte mesure
nécessaire (intérêt légitime) ; recueillir votre consentement lorsque la
réglementation l'exige. Tous les traitements ne reposent pas sur le
consentement.

DESTINATAIRES

Personnel habilité de 3E Technology Ltd et prestataires techniques agissant
pour son compte : hébergeur de l'infrastructure (Railway), Google (Google
Play Billing) et Apple (App Store) pour le paiement et la vérification des
achats, Google (Firebase Cloud Messaging) pour les notifications push,
prestataire(s) d'intelligence artificielle (OpenAI, et selon la
configuration Groq), Resend pour les e-mails transactionnels. Meta
Platforms, Inc. reçoit des événements de mesure non nominatifs UNIQUEMENT si
vous avez activé la mesure publicitaire. Auryel ne vend pas vos données.

TRANSFERTS INTERNATIONAUX

Des transferts hors de votre pays de résidence peuvent avoir lieu ; ils sont
encadrés par les garanties appropriées prévues par la réglementation
applicable.

CONSERVATION

Les données sont conservées pendant la durée nécessaire aux finalités
décrites et, lorsque nécessaire, pendant les durées imposées par les
obligations légales, comptables, fiscales, de sécurité et de prévention de
la fraude, ou pour la gestion d'éventuels litiges. Les durées précises
seront indiquées dans la version publiée.

SÉCURITÉ

Le jeton de session est stocké dans le coffre chiffré du système. Les
échanges avec l'API sont chiffrés en transit (HTTPS) ; l'application refuse
un fonctionnement en clair en production.

VOS DROITS

Sous réserve des conditions prévues par la réglementation applicable : accès,
rectification, effacement, limitation, opposition lorsque le traitement
repose sur l'intérêt légitime, portabilité lorsque applicable. Le prénom et
la date de naissance sont modifiables dans « Mon compte ». Pour exercer vos
droits : contact@auryelvoyance.com. Vous pouvez saisir l'autorité de
contrôle compétente de votre pays.

SUPPRESSION DU COMPTE

Depuis « Mon compte → Informations & confidentialité → Supprimer mon
compte », ou par e-mail à contact@auryelvoyance.com. La suppression entraîne
l'effacement des données personnelles associées lorsque leur conservation
n'est plus nécessaire, sous réserve des conservations imposées par la loi.

MODIFICATION

La présente politique peut être mise à jour. La version applicable est celle
publiée sur auryelvoyance.com.

CONTACT

3E Technology Ltd — contact@auryelvoyance.com — auryelvoyance.com
''';

const String kTermsInAppText = '''
ÉDITEUR ET OBJET

Auryel est édité par 3E Technology Ltd (company number 17179077),
71-75 Shelton Street, Covent Garden, London, United Kingdom, WC2H 9JQ.
Ces conditions régissent l'accès et l'utilisation de l'application :
création de compte, profil, consultations, tirages, contenus quotidiens,
méditation, Jeu Auryel, récompense de partage et abonnement Auryel Premium.
En utilisant l'application, vous acceptez ces conditions.

ACCÈS ET ÂGE

L'accès nécessite un appareil compatible et une connexion Internet, à vos
frais. Auryel est réservé aux personnes âgées de 18 ans ou plus. En créant
un compte, vous déclarez avoir au moins 18 ans ; l'application vérifie la
condition d'âge à partir de la date de naissance saisie.

COMPTE

La création d'un compte requiert une adresse e-mail valide et un mot de
passe. Vous fournissez des informations exactes, êtes responsable de la
confidentialité de vos identifiants et de l'activité de votre compte, et
prévenez contact@auryelvoyance.com en cas d'usage non autorisé.

SERVICE ET CONSULTATIONS

Auryel propose une expérience de voyance, tarot, guidance, consultation,
contenus quotidiens et méditation. Le temps de consultation disponible et
les droits sont gérés par le serveur, qui en est l'unique source.

INTELLIGENCE ARTIFICIELLE

Une partie de nos échanges est gérée par une intelligence artificielle. Les
réponses peuvent être générées ou assistées par de tels systèmes et peuvent
être inexactes ou incomplètes.

NATURE DES CONTENUS

Les contenus de voyance, tarot et guidance sont fournis à titre indicatif et
de divertissement. Ils ne constituent pas des certitudes, ne garantissent
aucun événement ou résultat futur, et ne remplacent pas l'avis d'un
professionnel qualifié : ils ne constituent ni un diagnostic médical, ni un
avis psychologique ou psychiatrique professionnel, ni un conseil juridique,
ni un conseil financier ou d'investissement. En cas d'urgence, contactez les
services d'urgence de votre pays. Aucune promesse de résultat n'est faite ;
vos décisions relèvent de votre seule responsabilité.

USAGES INTERDITS

Ne pas utiliser le service à des fins illicites ou portant atteinte aux
droits de tiers ; ne pas contourner les mécanismes de sécurité, de quota ou
de facturation ; ne pas créer plusieurs comptes pour obtenir indûment des
avantages (par exemple l'heure offerte), ni automatiser l'accès, ni
perturber le service ; ne pas transmettre de contenus illégaux ; ne pas
réutiliser les contenus en dehors d'un usage personnel.

DISPONIBILITÉ

Le service est fourni « en l'état » et « selon disponibilité ». Des
interruptions peuvent survenir.

SUPPRESSION, SUSPENSION, RÉSILIATION

Vous pouvez supprimer votre compte à tout moment depuis « Mon compte ».
L'éditeur peut suspendre ou résilier un compte en cas de manquement à ces
conditions, notamment fraude, abus des mécanismes de récompense ou de quota,
ou atteinte à la sécurité ; un avertissement préalable est adressé lorsque
cela est possible et proportionné.

PROPRIÉTÉ INTELLECTUELLE

Les contenus, marques, textes, interprétations, visuels et sons sont
protégés et restent la propriété de 3E Technology Ltd ou de ses partenaires.
Une licence personnelle, non exclusive et non transférable vous est concédée
pour la durée d'utilisation du service.

RESPONSABILITÉ

Dans les limites permises par la loi applicable, la responsabilité de
l'éditeur ne saurait être engagée pour les dommages indirects ni pour les
conséquences de décisions prises sur la base de contenus fournis à titre
indicatif. Aucune stipulation ne limite ou n'exclut les droits que la loi
impérative de votre pays de résidence vous accorde en tant que consommateur,
ni la responsabilité qui ne peut légalement être exclue.

SERVICES TIERS ET MODIFICATIONS

L'application s'appuie sur des services tiers (magasins pour le paiement,
application de partage de l'appareil, prestataires techniques), régis par
leurs propres conditions. Ces conditions peuvent être modifiées ; la version
applicable est celle publiée sur auryelvoyance.com.

DROIT APPLICABLE

Ces conditions sont régies par le droit anglais. Si vous êtes consommateur,
vous conservez le bénéfice des dispositions impératives et des protections
que la loi de votre pays de résidence habituelle vous accorde. Aucune clause
ne vous prive de ces droits.

CONTACT

contact@auryelvoyance.com
''';

const String kPremiumTermsInAppText = '''
AURYEL PREMIUM

Auryel Premium est un abonnement payant donnant accès à un volume de temps
de consultation et aux échanges illimités pendant ce temps.
Identifiant du produit : auryel_premium_monthly.
Prix commercial de référence : 7,99 € par mois. Le prix effectivement
facturé est celui affiché par le magasin (Google Play ou App Store) au
moment de l'achat, dans votre devise et selon votre région ; en cas de
différence, le prix du magasin fait foi.

CONTENU

8 heures de consultation par mois. Messages illimités pendant le temps de
consultation disponible. Le décompte du temps et des droits est géré par le
serveur.

PAIEMENT

L'abonnement est souscrit et facturé via votre compte Google Play ou Apple
App Store. Auryel ne collecte ni ne conserve vos coordonnées bancaires.
Aucun paiement ne se fait en dehors du magasin.

RENOUVELLEMENT

L'abonnement est mensuel et se renouvelle automatiquement à la fin de chaque
période, au prix alors en vigueur, sauf résiliation avant la date de
renouvellement, selon les règles du magasin.

RÉSILIATION ET EFFET

Vous pouvez résilier à tout moment depuis la gestion des abonnements de
votre magasin (Google Play → Abonnements, ou Réglages iOS → Abonnements).
L'application propose un raccourci « Gérer mon abonnement » qui ouvre la page
officielle du magasin ; Auryel ne résilie pas à votre place. En cas de
résiliation, l'abonnement reste actif jusqu'à la fin de la période déjà
payée et n'est pas renouvelé ensuite.

REMBOURSEMENTS ET RESTAURATION

Les demandes de remboursement sont traitées par le magasin selon ses règles.
Vos droits impératifs de consommateur demeurent réservés. Utilisez
« Restaurer mes achats » dans l'écran Premium après un changement d'appareil
ou une réinstallation.

RÉCOMPENSES — NON CONTRACTUELLES

L'heure offerte est accordée une fois par compte selon les règles décidées
par le serveur ; elle n'est pas cumulable par création de comptes multiples.
La récompense de partage (« 30 jours de partage = 1 heure »), le parcours
bien-être (« 30 jours = 15 minutes ») et le Jeu Auryel (5 à 15 minutes selon
la difficulté, dans la limite de 30 minutes par période de 7 jours) créditent
un temps de consultation UNIQUEMENT lorsque le serveur confirme le crédit ;
ce sont des bonus non contractuels, sans valeur monétaire, qui ne font pas
partie des prestations garanties de l'abonnement et ne sont jamais
convertibles en argent.

NON DISPONIBLE EN V1

L'achat d'une heure de consultation supplémentaire (2,90 €), le parrainage
et la boutique ne sont pas disponibles à ce jour et ne peuvent pas être
achetés ni présentés comme des avantages actifs.

COMPTE ET DISPONIBILITÉ

La suppression de votre compte Auryel n'annule pas un abonnement souscrit
auprès du magasin : résiliez-le séparément. Le service est fourni « selon
disponibilité ».

CONTACT

contact@auryelvoyance.com
''';
