import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import 'auth_service.dart';
import '../config/api_config.dart';
import 'cache_service.dart';

class UserService {
  final AuthService _authService = AuthService();
  final CacheService _cacheService = CacheService();

  // Usa a configuração centralizada da API
  static String get baseUrl => ApiConfig.baseUrl;

  // Obter headers com autenticação
  Map<String, String> _getHeaders() {
    final token = _authService.currentAccessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Obter dados do usuário atual (com cache)
  Future<User?> getCurrentUser({bool forceRefresh = false}) async {
    try {
      // Verificar se há token antes de fazer a requisição
      final token = _authService.currentAccessToken;
      if (token == null) {
        // Sem token, não há usuário autenticado
        return null;
      }

      // Tentar obter do cache primeiro (se não for refresh forçado)
      if (!forceRefresh) {
        final cachedUser = await _cacheService.getCachedUser();
        if (cachedUser != null) {
          return cachedUser;
        }
      }

      // Se não houver cache válido, buscar da API
      final response = await http.get(
        Uri.parse('$baseUrl/users/me'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final user = User.fromJson(decoded);
        
        // Salvar no cache
        await _cacheService.cacheUser(user);
        
        return user;
      } else if (response.statusCode == 404) {
        // Usuário não encontrado no MongoDB - isso é normal para novos usuários
        return null;
      } else if (response.statusCode == 401) {
        // Não autenticado - invalidar cache e retornar null
        await _cacheService.invalidateUserCache();
        return null;
      } else {
        // Outros erros - retornar cache se disponível
        final cachedUser = await _cacheService.getCachedUser();
        return cachedUser;
      }
    } catch (e) {
      // Em caso de erro de rede, tentar retornar do cache
      final cachedUser = await _cacheService.getCachedUser();
      if (cachedUser != null) {
        return cachedUser;
      }
      return null;
    }
  }

  // Criar ou atualizar usuário
  Future<User> createOrUpdateUser(String name) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users'),
        headers: _getHeaders(),
        body: json.encode({'name': name}),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final user = User.fromJson(decoded);
        
        // Atualizar cache
        await _cacheService.cacheUser(user);
        
        return user;
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to save user');
      }
    } catch (e) {

      rethrow;
    }
  }

  // Atualizar nome do usuário
  Future<User> updateUserName(String name) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/users/me'),
        headers: _getHeaders(),
        body: json.encode({'name': name}),
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final user = User.fromJson(decoded);
        
        // Atualizar cache
        await _cacheService.cacheUser(user);
        
        return user;
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to update user');
      }
    } catch (e) {

      rethrow;
    }
  }
}
