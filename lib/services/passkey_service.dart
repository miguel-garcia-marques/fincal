import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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
      print('[Passkey] Não é web, retornando false');
      return false; // Por enquanto, apenas suporte web
    }
    
    try {
      print('[Passkey] Verificando suporte...');
      
      // Verificar diretamente a API do navegador usando eval (mais confiável)
      try {
        final result = js.context.callMethod('eval', [
          'typeof navigator !== "undefined" && typeof navigator.credentials !== "undefined" && typeof navigator.credentials.create === "function" && typeof navigator.credentials.get === "function"'
        ]);
        if (result != null && result is bool && result) {
          print('[Passkey] ✅ Suporte detectado via Navigator API');
          return true;
        } else {
          print('[Passkey] Navigator.credentials não disponível');
        }
      } catch (e) {
        print('[Passkey] Erro ao verificar Navigator API: $e');
      }
      
      // Tentar usar função helper se disponível
      try {
        final helpersCheck = js.context.callMethod('eval', [
          'typeof window.webauthnHelpers !== "undefined" && typeof window.webauthnHelpers.isSupported === "function"'
        ]);
        if (helpersCheck == true) {
          print('[Passkey] webauthnHelpers encontrado');
          final result = js.context.callMethod('eval', [
            'window.webauthnHelpers.isSupported()'
          ]);
          if (result != null && result is bool) {
            print('[Passkey] Helper retornou: $result');
            return result;
          }
        } else {
          print('[Passkey] webauthnHelpers não encontrado');
        }
      } catch (e) {
        print('[Passkey] Erro ao usar helper: $e');
      }
      
      print('[Passkey] ❌ Suporte não detectado');
      return false;
    } catch (e) {
      print('[Passkey] Erro geral na verificação: $e');
      return false;
    }
  }

  // Registrar nova passkey
  Future<bool> registerPasskey({String? deviceType, String? name}) async {
    final prefs = await SharedPreferences.getInstance();
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
        Uri.parse('$_baseUrl/passkeys/register/options'),
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

      // Preparar opções usando funções JavaScript via eval
      // Verificar se helpers estão disponíveis
      final helpersCheck = js.context.callMethod('eval', [
        'typeof window.webauthnHelpers !== "undefined"'
      ]);
      if (helpersCheck != true) {
        throw Exception('WebAuthn helpers não disponíveis');
      }

      final userIdStr = optionsData['user']['id'] as String;

      // Preparar opções usando eval para construir o objeto completo
      // Isso é mais complexo, então vamos usar uma abordagem diferente
      // Criar o objeto de opções como string JSON e depois converter
      final excludeCredsJson = (optionsData['excludeCredentials'] as List?)
          ?.map((cred) {
            final credId = cred['id'] as String;
            return '{"id": window.webauthnHelpers.base64UrlToArrayBuffer("$credId"), "type": "${cred['type']}", "transports": ${jsonEncode(cred['transports'])}}';
          })
          .join(',');
      
      final excludeCredsStr = excludeCredsJson != null ? '[$excludeCredsJson]' : '[]';
      
      // Construir objeto completo via eval
      final publicKeyOptionsStr = '''
      {
        challenge: window.webauthnHelpers.base64UrlToArrayBuffer("$challenge"),
        rp: ${jsonEncode(optionsData['rp'])},
        user: {
          id: window.webauthnHelpers.base64UrlToArrayBuffer("$userIdStr"),
          name: ${jsonEncode(optionsData['user']['name'])},
          displayName: ${jsonEncode(optionsData['user']['displayName'])}
        },
        pubKeyCredParams: ${jsonEncode(optionsData['pubKeyCredParams'])},
        timeout: ${optionsData['timeout']},
        attestation: ${jsonEncode(optionsData['attestation'])},
        authenticatorSelection: ${jsonEncode(optionsData['authenticatorSelection'])},
        excludeCredentials: $excludeCredsStr
      }
      ''';

      // 2. Criar credencial e converter usando função wrapper JavaScript
      // Usar Promise.resolve para garantir que retorna uma Promise
      final credentialMapStr = await _executeAsyncJs(
        '''
        (async () => {
          try {
            const credential = await window.webauthnHelpers.createCredential($publicKeyOptionsStr);
            if (!credential) return null;
            const credentialObj = window.webauthnHelpers.credentialToObject(credential);
            return JSON.stringify(credentialObj);
          } catch (e) {
            return JSON.stringify({error: e.message});
          }
        })()
        '''
      );
      
      if (credentialMapStr == null) {
        throw Exception('Registro de passkey cancelado pelo usuário');
      }
      
      final credentialMapJson = credentialMapStr as String;
      final credentialMap = jsonDecode(credentialMapJson) as Map<String, dynamic>;
      
      // Verificar se há erro
      if (credentialMap.containsKey('error')) {
        throw Exception('Erro ao criar passkey: ${credentialMap['error']}');
      }

      // 3. Enviar credencial para o servidor para verificação
      final registerResponse = await http.post(
        Uri.parse('$_baseUrl/passkeys/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'credential': credentialMap,
          'challenge': challenge,
          'deviceType': deviceType ?? _detectDeviceType(),
          'name': name,
        }),
      );

      if (registerResponse.statusCode != 200) {
        final errorData = jsonDecode(registerResponse.body);
        throw Exception(errorData['message'] ?? 'Erro ao registrar passkey');
      }

      // Marcar que o usuário tem passkeys (para evitar tela de verificação de email)
      try {
        final currentUser = _authService.currentUser;
        if (currentUser != null) {
          await prefs.setBool('user_has_passkeys_${currentUser.id}', true);
        }
      } catch (e) {
        // Ignorar erros ao salvar preferência - não crítico
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
      // 1. Obter opções de autenticação do servidor com retry para 429
      http.Response? optionsResponse;
      int retryCount = 0;
      const maxRetries = 3;
      
      while (retryCount <= maxRetries) {
        try {
          optionsResponse = await http.post(
            Uri.parse('$_baseUrl/passkeys/authenticate/options'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'email': email}),
          );
          
          // Se não for 429, sair do loop
          if (optionsResponse.statusCode != 429) {
            break;
          }
          
          // Se for 429 e ainda temos tentativas, aguardar antes de retry
          if (retryCount < maxRetries) {
            final delaySeconds = (retryCount + 1) * 2; // Backoff exponencial: 2s, 4s, 6s
            print('[PasskeyService] Rate limit (429) atingido. Aguardando ${delaySeconds}s antes de tentar novamente...');
            await Future.delayed(Duration(seconds: delaySeconds));
            retryCount++;
            continue;
          }
        } catch (e) {
          // Se não for erro de rede, relançar
          if (!e.toString().contains('ClientException') && 
              !e.toString().contains('SocketException')) {
            rethrow;
          }
          // Erro de rede: tentar novamente se ainda temos tentativas
          if (retryCount < maxRetries) {
            final delaySeconds = (retryCount + 1) * 2;
            await Future.delayed(Duration(seconds: delaySeconds));
            retryCount++;
            continue;
          }
          rethrow;
        }
      }
      
      if (optionsResponse == null) {
        throw Exception('Erro ao obter opções de autenticação após múltiplas tentativas');
      }

      if (optionsResponse.statusCode != 200) {
        if (optionsResponse.statusCode == 404) {
          throw Exception('Nenhuma passkey encontrada para este email');
        }
        if (optionsResponse.statusCode == 429) {
          throw Exception('Muitas tentativas. Por favor, aguarde alguns instantes antes de tentar novamente.');
        }
        throw Exception('Erro ao obter opções de autenticação: ${optionsResponse.body}');
      }

      final optionsData = jsonDecode(optionsResponse.body);
      final challenge = optionsData['challenge'] as String;
      final userId = optionsData['userId'] as String?;

      if (userId == null) {
        throw Exception('Usuário não encontrado');
      }

      // Preparar opções usando eval
      final allowCredentialsJson = (optionsData['allowCredentials'] as List?)
          ?.map((cred) {
            final credId = cred['id'] as String;
            return '{"id": window.webauthnHelpers.base64UrlToArrayBuffer("$credId"), "type": "${cred['type']}", "transports": ${jsonEncode(cred['transports'])}}';
          })
          .join(',');
      
      final allowCredsStr = allowCredentialsJson != null ? '[$allowCredentialsJson]' : '[]';
      
      // Construir objeto de opções via eval
      final publicKeyOptionsStr = '''
      {
        challenge: window.webauthnHelpers.base64UrlToArrayBuffer("$challenge"),
        timeout: ${optionsData['timeout']},
        rpId: ${jsonEncode(optionsData['rpId'])},
        allowCredentials: $allowCredsStr,
        userVerification: ${jsonEncode(optionsData['userVerification'] ?? 'preferred')}
      }
      ''';

      // 2. Obter credencial e converter usando função wrapper JavaScript
      final credentialMapStr = await _executeAsyncJs(
        '''
        (async () => {
          try {
            const credential = await window.webauthnHelpers.getCredential($publicKeyOptionsStr);
            if (!credential) return null;
            const credentialObj = window.webauthnHelpers.authenticationResponseToObject(credential);
            return JSON.stringify(credentialObj);
          } catch (e) {
            return JSON.stringify({error: e.message});
          }
        })()
        '''
      );
      
      if (credentialMapStr == null) {
        throw Exception('Autenticação cancelada pelo usuário');
      }
      
      final credentialMapJson = credentialMapStr as String;
      final credentialMap = jsonDecode(credentialMapJson) as Map<String, dynamic>;
      
      // Verificar se há erro
      if (credentialMap.containsKey('error')) {
        throw Exception('Erro ao autenticar com passkey: ${credentialMap['error']}');
      }

      // 3. Enviar credencial para o servidor para verificação com retry para 429
      http.Response? authResponse;
      retryCount = 0;
      
      while (retryCount <= maxRetries) {
        try {
          authResponse = await http.post(
            Uri.parse('$_baseUrl/passkeys/authenticate'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'credential': credentialMap,
              'challenge': challenge,
              'userId': userId,
            }),
          );
          
          // Se não for 429, sair do loop
          if (authResponse.statusCode != 429) {
            break;
          }
          
          // Se for 429 e ainda temos tentativas, aguardar antes de retry
          if (retryCount < maxRetries) {
            final delaySeconds = (retryCount + 1) * 2; // Backoff exponencial: 2s, 4s, 6s
            print('[PasskeyService] Rate limit (429) atingido na autenticação. Aguardando ${delaySeconds}s antes de tentar novamente...');
            await Future.delayed(Duration(seconds: delaySeconds));
            retryCount++;
            continue;
          }
        } catch (e) {
          // Se não for erro de rede, relançar
          if (!e.toString().contains('ClientException') && 
              !e.toString().contains('SocketException')) {
            rethrow;
          }
          // Erro de rede: tentar novamente se ainda temos tentativas
          if (retryCount < maxRetries) {
            final delaySeconds = (retryCount + 1) * 2;
            await Future.delayed(Duration(seconds: delaySeconds));
            retryCount++;
            continue;
          }
          rethrow;
        }
      }
      
      if (authResponse == null) {
        throw Exception('Erro ao autenticar com passkey após múltiplas tentativas');
      }

      if (authResponse.statusCode != 200) {
        if (authResponse.statusCode == 429) {
          throw Exception('Muitas tentativas. Por favor, aguarde alguns instantes antes de tentar novamente.');
        }
        final errorData = jsonDecode(authResponse.body);
        throw Exception(errorData['message'] ?? 'Erro ao autenticar com passkey');
      }

      final authData = jsonDecode(authResponse.body);
      
      // Debug: verificar o que foi recebido do backend
      print('[PasskeyService] Resposta do backend:');
      print('[PasskeyService] - success: ${authData['success']}');
      print('[PasskeyService] - token: ${authData['token'] != null}');
      print('[PasskeyService] - access_token: ${authData['access_token'] != null}');
      print('[PasskeyService] - refresh_token: ${authData['refresh_token'] != null}');
      print('[PasskeyService] - magicLink: ${authData['magicLink'] != null}');
      print('[PasskeyService] - requiresPassword: ${authData['requiresPassword']}');
      
      return {
        'success': true,
        'userId': authData['userId'],
        'email': authData['email'],
        // Priorizar token do magic link (novo formato)
        'token': authData['token'], // Token do magic link para usar com verifyOTP
        // Manter compatibilidade com formato antigo (access_token/refresh_token)
        'access_token': authData['access_token'], // Token JWT (formato antigo)
        'refresh_token': authData['refresh_token'], // Refresh token (formato antigo)
        'expires_in': authData['expires_in'], // Tempo de expiração em segundos
        'token_type': authData['token_type'], // Tipo de token (bearer)
        'magicLink': authData['magicLink'], // Link completo como fallback
        'requiresPassword': authData['requiresPassword'], // Indica se precisa de senha
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
        Uri.parse('$_baseUrl/passkeys'),
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

  // Atualizar nome da passkey
  Future<bool> updatePasskeyName(String passkeyId, String? name) async {
    try {
      final token = _authService.currentAccessToken;
      if (token == null) {
        throw Exception('Usuário não autenticado');
      }

      final response = await http.put(
        Uri.parse('$_baseUrl/passkeys/$passkeyId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'name': name,
        }),
      );

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Erro ao atualizar nome da passkey');
      }

      return true;
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
        Uri.parse('$_baseUrl/passkeys/$passkeyId'),
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


  // Helper: Executar código JavaScript assíncrono e aguardar resultado
  Future<dynamic> _executeAsyncJs(String code) async {
    // Criar uma Promise wrapper que retorna o resultado
    final promiseCode = '''
      new Promise((resolve) => {
        (async () => {
          try {
            const result = await ($code);
            resolve(result);
          } catch (e) {
            resolve(JSON.stringify({error: e.message}));
          }
        })();
      })
    ''';
    
    // Usar eval para executar e retornar Promise
    // Nota: dart:js não suporta Promises diretamente, então vamos usar uma abordagem diferente
    // Vamos criar uma função global temporária
    final tempFuncName = '_tempPasskeyFunc_${DateTime.now().millisecondsSinceEpoch}';
    
    // Criar função temporária que retorna Promise
    js.context.callMethod('eval', [
      'window.$tempFuncName = function() { return $promiseCode; }'
    ]);
    
    // Chamar função e aguardar resultado usando polling
    // (Não ideal, mas funciona com dart:js)
    dynamic result;
    int attempts = 0;
    
    // Iniciar Promise
    js.context.callMethod('eval', [
      'window.$tempFuncName().then(r => { window._tempPasskeyResult = r; }).catch(e => { window._tempPasskeyResult = JSON.stringify({error: e.message}); })'
    ]);
    
    while (attempts < 100) { // Timeout de ~10 segundos
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        // Verificar se resultado está disponível
        final hasResult = js.context.callMethod('eval', [
          'typeof window._tempPasskeyResult !== "undefined"'
        ]);
        
        if (hasResult == true) {
          result = js.context.callMethod('eval', [
            'window._tempPasskeyResult'
          ]);
          
          // Limpar variáveis temporárias
          js.context.callMethod('eval', [
            'delete window.$tempFuncName; delete window._tempPasskeyResult;'
          ]);
          
          return result;
        }
      } catch (e) {
        // Continuar tentando
      }
      attempts++;
    }
    
    // Limpar em caso de timeout
    js.context.callMethod('eval', [
      'delete window.$tempFuncName; delete window._tempPasskeyResult;'
    ]);
    
    throw Exception('Timeout ao executar código JavaScript assíncrono');
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

