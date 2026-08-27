import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Erreur applicative renvoyée par le backend (statut HTTP hors 2xx, réponse
/// lisible). `code` reprend le champ `error` du JSON quand il existe.
class ApiException implements Exception {
  ApiException(this.statusCode, {this.code, this.message});

  final int statusCode;
  final String? code;
  final String? message;

  @override
  String toString() =>
      'ApiException($statusCode${code != null ? ', code: $code' : ''})';
}

/// 401 — la session (Bearer) n'est plus valide. Traité à part pour permettre
/// la purge du token + retour au login.
class ApiUnauthorizedException extends ApiException {
  ApiUnauthorizedException({super.code, super.message}) : super(401);
}

/// 402 — le backend refuse faute de crédit de consultation disponible.
/// Porte le corps décodé (contient `quota`, et `consultation: null`) pour
/// permettre l'affichage du mur Premium sans nouvel appel.
class ApiNoCreditException extends ApiException {
  ApiNoCreditException(this.body, {super.code, super.message}) : super(402);

  final Map<String, dynamic> body;
}

/// Le serveur n'a pas pu être joint (DNS, socket, timeout, TLS...). Ne signifie
/// PAS que la session est invalide : on ne détruit jamais le token là-dessus.
class ApiNetworkException implements Exception {
  ApiNetworkException(this.cause);

  final Object cause;

  @override
  String toString() => 'ApiNetworkException($cause)';
}

/// Client HTTP minimal du backend Auryel : base URL, JSON, en-tête Bearer
/// optionnel, mapping d'erreurs typé. Aucune logique métier ici.
class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl, this.timeout = const Duration(seconds: 15)})
      : _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _http;
  final String _baseUrl;
  final Duration timeout;

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) {
    return _send(
      () => _http.post(
        _uri(path),
        headers: _headers(bearer: bearer, json: true),
        body: jsonEncode(body),
      ),
    );
  }

  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) {
    return _send(
      () => _http.patch(
        _uri(path),
        headers: _headers(bearer: bearer, json: true),
        body: jsonEncode(body),
      ),
    );
  }

  Future<Map<String, dynamic>> getJson(String path, {String? bearer}) {
    return _send(
      () => _http.get(_uri(path), headers: _headers(bearer: bearer)),
    );
  }

  void close() => _http.close();

  // ---------------------------------------------------------------------------

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, String> _headers({String? bearer, bool json = false}) {
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (bearer != null && bearer.isNotEmpty) 'Authorization': 'Bearer $bearer',
    };
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException catch (e) {
      throw ApiNetworkException(e);
    } on SocketException catch (e) {
      throw ApiNetworkException(e);
    } on http.ClientException catch (e) {
      throw ApiNetworkException(e);
    } on HandshakeException catch (e) {
      throw ApiNetworkException(e);
    }

    final decoded = _decode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final code = decoded['error'] as String?;
    final message = decoded['message'] as String?;
    if (response.statusCode == 401) {
      throw ApiUnauthorizedException(code: code, message: message);
    }
    if (response.statusCode == 402) {
      throw ApiNoCreditException(decoded, code: code, message: message);
    }
    throw ApiException(response.statusCode, code: code, message: message);
  }

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return const {};
    try {
      final parsed = jsonDecode(body);
      return parsed is Map<String, dynamic> ? parsed : {'data': parsed};
    } catch (_) {
      return const {};
    }
  }
}
