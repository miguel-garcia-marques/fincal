import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import 'auth_service.dart';
import '../config/api_config.dart';
import 'cache_service.dart';
import '../utils/api_error_handler.dart';

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
      final currentUserId = _authService.currentUserId;
      
      if (token == null || currentUserId == null) {
        // Sem token ou sem ID de usuário, não há usuário autenticado
        // Limpar cache se houver
        await _cacheService.invalidateUserCache();
        return null;
      }

      // Tentar obter do cache primeiro (se não for refresh forçado)
      if (!forceRefresh) {
        final cachedUser = await _cacheService.getCachedUser();
        // Validar que o cache corresponde ao usuário atual
        if (cachedUser != null && cachedUser.userId == currentUserId) {
          return cachedUser;
        } else if (cachedUser != null) {
          // Cache de outro usuário - invalidar
          await _cacheService.invalidateUserCache();
        }
      }

      // Se não houver cache válido, buscar da API
      final response = await http.get(
        Uri.parse('$baseUrl/users/me'),
        headers: _getHeaders(),
      );

      // Verificar se é erro 401 e redirecionar para login
      await ApiErrorHandler.handleResponse(response);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final user = User.fromJson(decoded);
        
        // Salvar no cache
        await _cacheService.cacheUser(user);
        
        return user;
      } else if (response.statusCode == 404) {
        // Usuário não encontrado no MongoDB - isso é normal para novos usuários
        return null;
      } else {
        // Outros erros - retornar cache se disponível
        final cachedUser = await _cacheService.getCachedUser();
        return cachedUser;
      }
    } catch (e) {
      // Se for erro 401, já foi tratado e redirecionado - não retornar cache
      if (e.toString().contains('Unauthorized')) {
        await _cacheService.invalidateUserCache();
        rethrow;
      }
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

      // Verificar se é erro 401 e redirecionar para login
      await ApiErrorHandler.handleResponse(response);

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
      // Primeiro atualizar no Supabase
      try {
        final authService = AuthService();
        await authService.updateDisplayName(name);
      } catch (e) {
        // Continuar mesmo se falhar ao atualizar no Supabase
        // O MongoDB será atualizado de qualquer forma
      }
      
      // Depois atualizar no MongoDB
      final response = await http.put(
        Uri.parse('$baseUrl/users/me'),
        headers: _getHeaders(),
        body: json.encode({'name': name}),
      );

      // Verificar se é erro 401 e redirecionar para login
      await ApiErrorHandler.handleResponse(response);

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

  // Atualizar foto de perfil
  Future<User> updateProfilePicture(String profilePictureUrl) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/users/me'),
        headers: _getHeaders(),
        body: json.encode({'profilePictureUrl': profilePictureUrl}),
      );

      // Verificar se é erro 401 e redirecionar para login
      await ApiErrorHandler.handleResponse(response);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final user = User.fromJson(decoded);
        
        // Atualizar cache
        await _cacheService.cacheUser(user);
        
        return user;
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to update profile picture');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Deletar conta do usuário e todos os dados associados
  Future<void> deleteAccount() async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/users/me'),
        headers: _getHeaders(),
      );

      // Verificar se é erro 401 e redirecionar para login
      await ApiErrorHandler.handleResponse(response);

      if (response.statusCode == 200) {
        // Limpar cache após deletar conta
        await _cacheService.invalidateUserCache();
        await _cacheService.clearAllWalletMembersCache();
        await _cacheService.invalidateWalletsCache();
        await _cacheService.clearAllInvitesCache();
        await _cacheService.clearCache();
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to delete account');
      }
    } catch (e) {
      rethrow;
    }
  }
}
