// Champs privés initialisés par des paramètres nommés publics de nom différent.
// ignore_for_file: prefer_initializing_formals
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Identifiant d'INSTALLATION Auryel — signal anti-abus « heure gratuite ».
///
/// CE N'EST PAS UNE DONNÉE DE COMPTE :
///  - aléatoire, 128 bits d'entropie (`Random.secure()`), aucune dérivation
///    d'email / user_id / prénom / date de naissance / appareil / modèle / IP /
///    MAC / IMEI / ANDROID_ID / Advertising ID ;
///  - stocké dans le stockage chiffré de l'OS, clé DÉDIÉE
///    [SecureInstallationIdStore.storageKey] — jamais dans `TokenStore`,
///    jamais dans `SharedPreferences` ;
///  - **CONSERVÉ** au logout, au changement de compte, à la suppression de
///    compte (`LocalUserData.clearPersonal`, `forgetLocalIdentity`) — c'est
///    justement ce qui permet de reconnaître une même installation qui recrée
///    des comptes ;
///  - **disparaît normalement à la désinstallation** de l'app (aucune tentative
///    de contournement).
///
/// L'heure gratuite reste décidée par le SERVEUR. Cet identifiant est
/// uniquement un signal transmis (dans un lot ultérieur) ; il n'accorde AUCUN
/// droit côté Flutter. Cf. `docs/installation_id_anti_abuse.md`.
abstract class InstallationIdStore {
  /// Renvoie l'identifiant d'installation, en le créant + persistant au premier
  /// appel. Idempotent : toujours la même valeur pour la vie de l'installation.
  /// Ne lève jamais.
  Future<String> getOrCreate();
}

/// Clé de stockage (versionnée).
const String kInstallationIdStorageKey = 'auryel_installation_id_v1';

/// Format attendu : 32 caractères hexadécimaux minuscules = 128 bits.
final RegExp _installationIdPattern = RegExp(r'^[0-9a-f]{32}$');

/// `true` si [value] est un identifiant d'installation bien formé.
bool isValidInstallationId(String? value) =>
    value != null && _installationIdPattern.hasMatch(value);

/// Génère un identifiant : 16 octets de `Random.secure()` -> 32 hex.
/// Aucun timestamp, aucun compteur, aucun hash d'email.
String generateInstallationId([Random? random]) {
  final rnd = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Implémentation réelle : `FlutterSecureStorage` (Keystore Android / Keychain
/// iOS), MÊME mécanisme que [SecureTokenStore] mais clé et cycle de vie
/// distincts.
class SecureInstallationIdStore implements InstallationIdStore {
  SecureInstallationIdStore({FlutterSecureStorage? storage, Random? random})
    : _storage = storage ?? const FlutterSecureStorage(),
      _random = random ?? Random.secure();

  static const String storageKey = kInstallationIdStorageKey;

  final FlutterSecureStorage _storage;
  final Random _random;

  /// Cache PROCESSUS : garantit une valeur stable pendant toute la session même
  /// si l'écriture disque a échoué (cf. [_persistedOk]).
  String? _cached;

  /// `false` tant qu'une écriture disque réussie n'a pas confirmé la
  /// persistance. Si l'écriture échoue, [getOrCreate] renvoie quand même un id
  /// valide pour la session, mais il sera RÉGÉNÉRÉ au prochain lancement.
  bool _persistedOk = false;

  /// `true` si l'identifiant courant a bien été persisté sur disque.
  bool get isPersisted => _persistedOk;

  @override
  Future<String> getOrCreate() async {
    final cached = _cached;
    if (cached != null) return cached;

    String? existing;
    try {
      existing = await _storage.read(key: storageKey);
    } catch (_) {
      existing = null; // lecture impossible -> on régénère
    }
    if (isValidInstallationId(existing)) {
      _cached = existing;
      _persistedOk = true;
      return existing!;
    }

    final fresh = generateInstallationId(_random);
    try {
      await _storage.write(key: storageKey, value: fresh);
      _persistedOk = true;
    } catch (_) {
      // Écriture impossible : on NE prétend PAS que c'est persistant.
      // Aucun repli SharedPreferences silencieux (choix explicite : cette clé
      // ne doit vivre que dans le stockage chiffré).
      _persistedOk = false;
    }
    _cached = fresh;
    return fresh;
  }
}

/// Implémentation mémoire — tests uniquement. Simule un stockage persistant
/// (`_stored`) et, si [failWrites], une écriture disque qui échoue.
class InMemoryInstallationIdStore implements InstallationIdStore {
  InMemoryInstallationIdStore({
    String? stored,
    this.failWrites = false,
    Random? random,
  }) : _stored = stored,
       _random = random ?? Random.secure();

  String? _stored;
  final bool failWrites;
  final Random _random;
  String? _cached;
  bool persistedOk = false;

  /// Ce qui est « sur disque » (pour vérifier la persistance dans les tests).
  String? get stored => _stored;

  @override
  Future<String> getOrCreate() async {
    final cached = _cached;
    if (cached != null) return cached;
    if (isValidInstallationId(_stored)) {
      _cached = _stored;
      persistedOk = true;
      return _stored!;
    }
    final fresh = generateInstallationId(_random);
    if (!failWrites) {
      _stored = fresh;
      persistedOk = true;
    } else {
      persistedOk = false;
    }
    _cached = fresh;
    return fresh;
  }
}
