import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cache_service.dart';
import 'wallet_storage_service.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final CacheService _cacheService = CacheService();
  final WalletStorageService _walletStorageService = WalletStorageService();
  
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
      // Se já houver uma sessão ativa, fazer logout completo primeiro para evitar conflitos
      if (_supabase.auth.currentSession != null) {
        try {
          // Fazer logout completo (limpa tudo)
          await signOut();
        } catch (e) {
          // Se falhar, tentar apenas logout do Supabase
          try {
            await _supabase.auth.signOut();
            await Future.delayed(const Duration(milliseconds: 200));
          } catch (e2) {
            // Ignorar erros no logout - continuar mesmo assim
          }
        }
      }
      
      return await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      rethrow;
    }
  }

  // Criar conta com email e senha
  Future<AuthResponse> signUpWithEmail(String email, String password, {String? displayName}) async {
    try {
      return await _supabase.auth.signUp(
        email: email,
        password: password,
        data: displayName != null ? {'display_name': displayName} : null,
      );
    } catch (e) {
      rethrow;
    }
  }

  // Fazer logout
  Future<void> signOut() async {
    // Limpar todos os caches primeiro
    await _cacheService.invalidateUserCache();
    await _cacheService.clearAllWalletMembersCache();
    await _cacheService.invalidateWalletsCache();
    await _cacheService.clearAllInvitesCache();
    await _cacheService.clearCache();
    
    // Limpar wallet ativa
    await _walletStorageService.clearActiveWalletId();
    
    // Limpar dados pendentes do login
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_user_name');
      await prefs.remove('pending_user_email');
    } catch (e) {
      // Ignorar erros ao limpar dados pendentes
    }
    
    // Fazer logout do Supabase por último
    await _supabase.auth.signOut();
    
    // Aguardar um pouco para garantir que o logout foi processado completamente
    await Future.delayed(const Duration(milliseconds: 300));
  }

  // Recuperar senha
  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  // Atualizar Display Name do usuário no Supabase
  Future<void> updateDisplayName(String displayName) async {
    try {
      await _supabase.auth.updateUser(
        UserAttributes(
          data: {
            'display_name': displayName,
          },
        ),
      );
    } catch (e) {
      rethrow;
    }
  }
}
