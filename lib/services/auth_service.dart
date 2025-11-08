import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Getter público para acessar o cliente Supabase
  SupabaseClient get supabase => _supabase;

  // Obter o usuário atual
  User? get currentUser => _supabase.auth.currentUser;

  // Obter o ID do usuário atual
  String? get currentUserId => _supabase.auth.currentUser?.id;

  // Obter o token de acesso atual
  String? get currentAccessToken => _supabase.auth.currentSession?.accessToken;

  // Verificar se o usuário está autenticado
  bool get isAuthenticated => _supabase.auth.currentUser != null;

  // Stream de mudanças de autenticação
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  // Fazer login com email e senha
  Future<AuthResponse> signInWithEmail(String email, String password) async {
    try {
      return await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      rethrow;
    }
  }

  // Criar conta com email e senha
  Future<AuthResponse> signUpWithEmail(String email, String password) async {
    try {
      return await _supabase.auth.signUp(
        email: email,
        password: password,
      );
    } catch (e) {
      rethrow;
    }
  }

  // Fazer logout
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // Recuperar senha
  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }
}

