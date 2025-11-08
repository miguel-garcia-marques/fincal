import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import 'auth_service.dart';

class UserService {
  final AuthService _authService = AuthService();

  static const String baseUrl = 'http://localhost:3000/api';

  // Obter headers com autenticação
  Map<String, String> _getHeaders() {
    final token = _authService.currentAccessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Obter dados do usuário atual
  Future<User?> getCurrentUser() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users/me'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return User.fromJson(decoded);
      } else if (response.statusCode == 404) {
        // Usuário não encontrado no MongoDB
        return null;
      } else {
        throw Exception('Failed to load user: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching user: $e');
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
        return User.fromJson(decoded);
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to save user');
      }
    } catch (e) {
      print('Error saving user: $e');
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
        return User.fromJson(decoded);
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to update user');
      }
    } catch (e) {
      print('Error updating user: $e');
      rethrow;
    }
  }
}

