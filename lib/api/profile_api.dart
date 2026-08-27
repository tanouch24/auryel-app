import 'api_client.dart';
import '../data/app_profile.dart';

/// Endpoints du profil app (B4.3). Réutilise [ApiClient] et le Bearer F1.
///
///   GET   /api/app/profile   (Bearer) -> AppProfile
///   PATCH /api/app/profile   (Bearer) { guide?, prenom?, date_naissance? } -> AppProfile
///
/// Le backend calcule lui-même chemin_de_vie / signe_zodiaque. On n'envoie
/// jamais user_id / phone / genre / portrait / abonnement.
class ProfileApi {
  ProfileApi(this._client);

  final ApiClient _client;

  Future<AppProfile> getProfile(String bearer) async {
    final json = await _client.getJson('/api/app/profile', bearer: bearer);
    return AppProfile.fromJson(json);
  }

  /// PATCH partiel : seuls les champs non nuls sont envoyés.
  Future<AppProfile> patchProfile(
    String bearer, {
    String? guide,
    String? prenom,
    String? dateNaissance,
  }) async {
    final body = <String, dynamic>{
      'guide': ?guide,
      'prenom': ?prenom,
      'date_naissance': ?dateNaissance,
    };
    final json = await _client.patchJson('/api/app/profile', body, bearer: bearer);
    return AppProfile.fromJson(json);
  }
}
