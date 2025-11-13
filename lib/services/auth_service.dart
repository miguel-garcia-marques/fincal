import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import 'cache_service.dart';
import 'wallet_storage_service.dart';
import '../config/app_config.dart';

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

  // Obter URL de redirecionamento para verificação de email
  String? getRedirectUrl() {
    if (!kIsWeb) {
      // Para apps mobile, não precisa de redirectTo
      return null;
    }
    
    // Primeiro, verificar se há uma URL configurada explicitamente via --dart-define
    const envUrl = String.fromEnvironment('APP_BASE_URL');
    if (envUrl.isNotEmpty) {
      // Remover barra final se houver
      return envUrl.endsWith('/') ? envUrl.substring(0, envUrl.length - 1) : envUrl;
    }
    
    // Verificar se está em produção
    const isProd = bool.fromEnvironment('dart.vm.product');
    
    // Verificar se há uma URL configurada no AppConfig
    // Em produção, sempre priorizar a URL do AppConfig se configurada
    final configuredUrl = AppConfig.getAppBaseUrl();
    if (configuredUrl != null && configuredUrl.isNotEmpty) {
      // Remover barra final se houver (já removido no AppConfig, mas garantir)
      return configuredUrl.endsWith('/') 
          ? configuredUrl.substring(0, configuredUrl.length - 1) 
          : configuredUrl;
    }
    
    // Se estiver em produção e não houver URL configurada, retornar null
    // O Supabase usará a URL padrão configurada no dashboard
    if (isProd) {
      return null;
    }
    
    // Em desenvolvimento, tentar detectar a URL atual
    try {
      // Obter a URL base atual
      final uri = Uri.base;
      final host = uri.host.toLowerCase();
      
      // Se estiver em localhost ou 127.0.0.1, usar localhost
      if (host == 'localhost' || host == '127.0.0.1' || host.isEmpty) {
        return '${uri.scheme}://$host${uri.hasPort ? ':${uri.port}' : ''}';
      }
      
      // Se não for localhost, construir URL sem porta
      final redirectUrl = '${uri.scheme}://$host';
      return redirectUrl;
    } catch (e) {
      // Se falhar, tentar usar window.location
      try {
        if (kIsWeb) {
          final location = html.window.location;
          final host = location.host.toLowerCase();
          
          // Se for localhost, usar localhost
          if (host.contains('localhost') || host.contains('127.0.0.1') || host.isEmpty) {
            return location.port.isNotEmpty 
                ? '${location.protocol}//$host:${location.port}'
                : '${location.protocol}//$host';
          }
          
          // Em produção, não incluir porta
          return '${location.protocol}//$host';
        }
      } catch (e2) {
        // Se ainda falhar, retornar null (Supabase usará o padrão configurado no dashboard)
      }
      return null;
    }
  }

  // Criar conta com email e senha
  Future<AuthResponse> signUpWithEmail(String email, String password, {String? displayName}) async {
    try {
      // Obter URL de redirecionamento
      final redirectTo = getRedirectUrl();
      
      return await _supabase.auth.signUp(
        email: email,
        password: password,
        data: displayName != null ? {'display_name': displayName} : null,
        emailRedirectTo: redirectTo,
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
    
    // Tentar fazer logout do Supabase com tratamento de erros robusto
    // Se falhar (erro de rede, etc), continuar mesmo assim pois já limpamos tudo localmente
    try {
      // Verificar se há sessão antes de tentar logout
      if (_supabase.auth.currentSession != null) {
        // Tentar logout com timeout para evitar travamento
        await _supabase.auth.signOut().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            // Se timeout, limpar sessão localmente
            // O Supabase vai limpar automaticamente quando conseguir conectar
          },
        );
      }
    } catch (e) {
      // Se falhar o logout do Supabase (erro de rede, timeout, etc),
      // continuar mesmo assim pois já limpamos todos os dados locais
      // O importante é garantir que o usuário possa continuar usando o app
      // A sessão do Supabase será limpa quando conseguir conectar novamente
      print('Aviso: Erro ao fazer logout do Supabase (continuando mesmo assim): $e');
      
      // O Supabase gerencia seus próprios tokens localmente
      // Se houver erro de rede, a sessão será limpa quando conseguir conectar novamente
    }
    
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

  // Deletar conta do usuário no Supabase Auth
  // Nota: O Supabase não permite deletar o próprio usuário diretamente via SDK
  // Isso deve ser feito através do Admin API ou pelo usuário através do dashboard
  // Por enquanto, apenas fazemos logout e deixamos o backend lidar com a limpeza
  Future<void> deleteAccount() async {
    try {
      // Fazer logout completo
      await signOut();
      
      // Nota: Para deletar completamente do Supabase Auth, seria necessário usar Admin API
      // ou o usuário pode deletar manualmente através do dashboard do Supabase
      // O backend já deleta todos os dados do MongoDB
    } catch (e) {
      rethrow;
    }
  }
}
