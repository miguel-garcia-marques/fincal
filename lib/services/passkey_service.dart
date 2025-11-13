import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'auth_service.dart';

// Para Flutter Web, usar dart:js para acessar funções JavaScript
import 'dart:js' as js;

class PasskeyService {
  final AuthService _authService = AuthService();
  final String _baseUrl = ApiConfig.baseUrl;

  // Verificar se passkeys são suportadas
  bool get isSupported {
    if (!kIsWeb) {
      return false; // Por enquanto, apenas suporte web
    }
    
    try {
      final helpers = js.context['webauthnHelpers'];
      if (helpers == null) return false;
      final helpersObj = js.JsObject.jsify(helpers);
      return helpersObj.callMethod('isSupported') as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  // Registrar nova passkey
  Future<bool> registerPasskey({String? deviceType}) async {
    if (!isSupported) {
      throw Exception('Passkeys não são suportadas neste dispositivo');
    }

    try {
      // Obter token de autenticação
      final token = _authService.currentAccessToken;
      if (token == null) {
        throw Exception('Usuário não autenticado');
      }

      // 1. Obter opções de registro do servidor
      final optionsResponse = await http.post(
        Uri.parse('$_baseUrl/api/passkeys/register/options'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (optionsResponse.statusCode != 200) {
        throw Exception('Erro ao obter opções de registro: ${optionsResponse.body}');
      }

      final optionsData = jsonDecode(optionsResponse.body);
      final challenge = optionsData['challenge'] as String;

      // Preparar opções usando funções JavaScript
      final helpers = js.context['webauthnHelpers'];
      if (helpers == null) {
        throw Exception('WebAuthn helpers não disponíveis');
      }
      final helpersObj = js.JsObject.jsify(helpers);

      // Converter challenge e userID usando função JavaScript
      final challengeBuffer = helpersObj.callMethod('base64UrlToArrayBuffer', [challenge]);
      final userIdBuffer = helpersObj.callMethod('base64UrlToArrayBuffer', [optionsData['user']['id'] as String]);

      // Preparar opções
      final excludeCreds = (optionsData['excludeCredentials'] as List?)
          ?.map((cred) {
            final credIdBuffer = helpersObj.callMethod('base64UrlToArrayBuffer', [cred['id'] as String]);
            return js.JsObject.jsify({
              'id': credIdBuffer,
              'type': cred['type'],
              'transports': cred['transports'],
            });
          })
          .toList();

      final publicKeyOptions = js.JsObject.jsify({
        'challenge': challengeBuffer,
        'rp': {
          'name': optionsData['rp']['name'],
          'id': optionsData['rp']['id'],
        },
        'user': {
          'id': userIdBuffer,
          'name': optionsData['user']['name'],
          'displayName': optionsData['user']['displayName'],
        },
        'pubKeyCredParams': optionsData['pubKeyCredParams'],
        'timeout': optionsData['timeout'],
        'attestation': optionsData['attestation'],
        'authenticatorSelection': optionsData['authenticatorSelection'],
        'excludeCredentials': excludeCreds,
      });

      // 2. Criar credencial usando função JavaScript helper
      final credentialJs = await helpersObj.callMethod('createCredential', [publicKeyOptions]);
      
      if (credentialJs == null) {
        throw Exception('Registro de passkey cancelado pelo usuário');
      }

      // Converter credencial para objeto usando função JavaScript
      final credentialMapJs = helpersObj.callMethod('credentialToObject', [credentialJs]);
      final credentialMap = (js.context['JSON'].callMethod('parse', [
        js.context['JSON'].callMethod('stringify', [credentialMapJs])
      ]) as Map).cast<String, dynamic>();

      // 3. Enviar credencial para o servidor para verificação
      final registerResponse = await http.post(
        Uri.parse('$_baseUrl/api/passkeys/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'credential': credentialMap,
          'challenge': challenge,
          'deviceType': deviceType ?? _detectDeviceType(),
        }),
      );

      if (registerResponse.statusCode != 200) {
        final errorData = jsonDecode(registerResponse.body);
        throw Exception(errorData['message'] ?? 'Erro ao registrar passkey');
      }

      return true;
    } catch (e) {
      rethrow;
    }
  }

  // Autenticar com passkey
  Future<Map<String, dynamic>> authenticateWithPasskey(String email) async {
    if (!isSupported) {
      throw Exception('Passkeys não são suportadas neste dispositivo');
    }

    try {
      // 1. Obter opções de autenticação do servidor
      final optionsResponse = await http.post(
        Uri.parse('$_baseUrl/api/passkeys/authenticate/options'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'email': email}),
      );

      if (optionsResponse.statusCode != 200) {
        if (optionsResponse.statusCode == 404) {
          throw Exception('Nenhuma passkey encontrada para este email');
        }
        throw Exception('Erro ao obter opções de autenticação: ${optionsResponse.body}');
      }

      final optionsData = jsonDecode(optionsResponse.body);
      final challenge = optionsData['challenge'] as String;
      final userId = optionsData['userId'] as String?;

      if (userId == null) {
        throw Exception('Usuário não encontrado');
      }

      // Preparar opções usando funções JavaScript
      final helpers = js.context['webauthnHelpers'];
      if (helpers == null) {
        throw Exception('WebAuthn helpers não disponíveis');
      }
      final helpersObj = js.JsObject.jsify(helpers);

      final challengeBuffer = helpersObj.callMethod('base64UrlToArrayBuffer', [challenge]);
      
      final allowCredentials = (optionsData['allowCredentials'] as List?)
          ?.map((cred) {
            final credIdBuffer = helpersObj.callMethod('base64UrlToArrayBuffer', [cred['id'] as String]);
            return js.JsObject.jsify({
              'id': credIdBuffer,
              'type': cred['type'],
              'transports': cred['transports'],
            });
          })
          .toList();

      final publicKeyOptions = js.JsObject.jsify({
        'challenge': challengeBuffer,
        'timeout': optionsData['timeout'],
        'rpId': optionsData['rpId'],
        'allowCredentials': allowCredentials,
        'userVerification': optionsData['userVerification'] ?? 'preferred',
      });

      // 2. Obter credencial usando função JavaScript helper
      final credentialJs = await helpersObj.callMethod('getCredential', [publicKeyOptions]);
      
      if (credentialJs == null) {
        throw Exception('Autenticação cancelada pelo usuário');
      }

      // Converter credencial para objeto usando função JavaScript
      final credentialMapJs = helpersObj.callMethod('authenticationResponseToObject', [credentialJs]);
      final credentialMap = (js.context['JSON'].callMethod('parse', [
        js.context['JSON'].callMethod('stringify', [credentialMapJs])
      ]) as Map).cast<String, dynamic>();

      // 3. Enviar credencial para o servidor para verificação
      final authResponse = await http.post(
        Uri.parse('$_baseUrl/api/passkeys/authenticate'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'credential': credentialMap,
          'challenge': challenge,
          'userId': userId,
        }),
      );

      if (authResponse.statusCode != 200) {
        final errorData = jsonDecode(authResponse.body);
        throw Exception(errorData['message'] ?? 'Erro ao autenticar com passkey');
      }

      final authData = jsonDecode(authResponse.body);
      return {
        'success': true,
        'userId': authData['userId'],
        'email': authData['email'],
      };
    } catch (e) {
      rethrow;
    }
  }

  // Listar passkeys do usuário
  Future<List<Map<String, dynamic>>> listPasskeys() async {
    try {
      final token = _authService.currentAccessToken;
      if (token == null) {
        throw Exception('Usuário não autenticado');
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/api/passkeys'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Erro ao listar passkeys: ${response.body}');
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      rethrow;
    }
  }

  // Deletar passkey
  Future<bool> deletePasskey(String passkeyId) async {
    try {
      final token = _authService.currentAccessToken;
      if (token == null) {
        throw Exception('Usuário não autenticado');
      }

      final response = await http.delete(
        Uri.parse('$_baseUrl/api/passkeys/$passkeyId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Erro ao deletar passkey: ${response.body}');
      }

      return true;
    } catch (e) {
      rethrow;
    }
  }


  // Helper: Detectar tipo de dispositivo
  String _detectDeviceType() {
    if (!kIsWeb) {
      return 'mobile';
    }
    
    try {
      final userAgent = js.context['navigator']['userAgent'].toString().toLowerCase();
      if (userAgent.contains('mobile') || userAgent.contains('android')) {
        return 'mobile';
      } else if (userAgent.contains('mac') || userAgent.contains('ios')) {
        return 'desktop-mac';
      } else if (userAgent.contains('windows')) {
        return 'desktop-windows';
      } else if (userAgent.contains('linux')) {
        return 'desktop-linux';
      }
    } catch (e) {
      // Ignorar erro
    }
    
    return 'desktop';
  }
}

