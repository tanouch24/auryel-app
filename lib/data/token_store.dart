import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage du jeton de session (Bearer). Interface abstraite pour que les
/// tests injectent une implémentation mémoire — l'implémentation réelle
/// [SecureTokenStore] passe UNIQUEMENT par le stockage chiffré de l'OS
/// (Keystore Android / Keychain iOS), jamais par SharedPreferences.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'auryel_session_token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Implémentation mémoire — tests uniquement (jamais persistée).
class InMemoryTokenStore implements TokenStore {
  InMemoryTokenStore([this._value]);

  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String token) async => _value = token;

  @override
  Future<void> clear() async => _value = null;
}
