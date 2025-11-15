import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/wallet_storage_service.dart';
import '../services/wallet_service.dart';
import '../services/passkey_service.dart';
import '../models/wallet.dart';
import '../models/user.dart';

/// Estado do processo de onboarding do usuário
enum OnboardingState {
  /// Usuário não está autenticado
  notAuthenticated,
  
  /// Email não foi verificado
  emailNotVerified,
  
  /// Passkey não foi verificada (usuário tem passkeys mas precisa autenticar)
  passkeyNotVerified,
  
  /// Email verificado mas falta foto de perfil
  needsProfilePicture,
  
  /// Falta selecionar wallet
  needsWalletSelection,
  
  /// Onboarding completo - pode acessar a app
  completed,
}

/// Orquestrador centralizado para gerenciar o fluxo de onboarding
/// Evita loops e conflitos de navegação
class OnboardingOrchestrator {
  final AuthService _authService;
  final UserService _userService;
  final WalletStorageService _walletStorageService;
  final WalletService _walletService;
  final PasskeyService _passkeyService;
  
  OnboardingOrchestrator({
    AuthService? authService,
    UserService? userService,
    WalletStorageService? walletStorageService,
    WalletService? walletService,
    PasskeyService? passkeyService,
  }) : _authService = authService ?? AuthService(),
       _userService = userService ?? UserService(),
       _walletStorageService = walletStorageService ?? WalletStorageService(),
       _walletService = walletService ?? WalletService(),
       _passkeyService = passkeyService ?? PasskeyService();

  /// Determina o estado atual do onboarding do usuário
  /// Retorna o próximo passo necessário ou completed se tudo estiver ok
  Future<OnboardingState> getCurrentState() async {
    try {
      // 1. Verificar autenticação
      final isAuthenticated = _authService.isAuthenticated;
      final currentUser = _authService.currentUser;
      
      if (!isAuthenticated || currentUser == null) {
        print('[OnboardingOrchestrator] Usuário não autenticado');
        return OnboardingState.notAuthenticated;
      }
      
      // 2. Verificar se email foi confirmado OU se usuário existe no MongoDB
      // Se o usuário existe no MongoDB, significa que a conta foi criada e email foi verificado
      final emailConfirmed = currentUser.emailConfirmedAt != null;
      
      // Verificar MongoDB uma única vez (reutilizar resultado)
      User? mongoUser;
      try {
        mongoUser = await _userService.getCurrentUser(forceRefresh: false).timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            print('[OnboardingOrchestrator] Timeout ao buscar usuário no MongoDB');
            return null;
          },
        );
      } catch (e) {
        print('[OnboardingOrchestrator] Erro ao buscar usuário no MongoDB: $e');
        mongoUser = null;
      }
      
      // Se o email não foi confirmado no Supabase, verificar alternativas
      if (!emailConfirmed) {
        // Verificar se há passkeys registradas
        bool hasPasskeys = false;
        try {
          final prefs = await SharedPreferences.getInstance();
          hasPasskeys = prefs.getBool('user_has_passkeys_${currentUser.id}') ?? false;
        } catch (e) {
          print('[OnboardingOrchestrator] Erro ao verificar passkeys: $e');
        }
        
        // Se usuário existe no MongoDB OU tem passkeys, considerar email verificado
        if (mongoUser != null || hasPasskeys) {
          print('[OnboardingOrchestrator] Email considerado verificado (mongoUser: ${mongoUser != null}, passkeys: $hasPasskeys)');
          // Continuar para próxima etapa
        } else {
          // Usuário não tem passkeys e não existe no MongoDB - precisa verificar email
          print('[OnboardingOrchestrator] Email não verificado - mostrando tela de verificação');
          return OnboardingState.emailNotVerified;
        }
      } else {
        print('[OnboardingOrchestrator] Email confirmado no Supabase');
      }
      
      // 3. Se usuário não existe no MongoDB ainda, tentar criar (mas não bloquear se falhar)
      if (mongoUser == null) {
        print('[OnboardingOrchestrator] Usuário não encontrado no MongoDB - tentando criar...');
        try {
          // Tentar criar usuário automaticamente (pode falhar se não tiver permissões)
          // Não bloquear o fluxo se falhar - usuário pode ser criado depois
          await _userService.getCurrentUser(forceRefresh: true).timeout(
            const Duration(seconds: 2),
            onTimeout: () => null,
          );
          // Recarregar após tentativa de criação
          mongoUser = await _userService.getCurrentUser(forceRefresh: false).timeout(
            const Duration(seconds: 2),
            onTimeout: () => null,
          );
        } catch (e) {
          print('[OnboardingOrchestrator] Erro ao criar usuário no MongoDB: $e');
          // Continuar mesmo se falhar - não bloquear o fluxo
        }
        
        // Se ainda não existe após tentativa, mas email está confirmado, continuar mesmo assim
        // O usuário será criado quando necessário
        if (mongoUser == null && emailConfirmed) {
          print('[OnboardingOrchestrator] Email confirmado mas usuário não existe no MongoDB - continuando mesmo assim');
          // Continuar para próxima etapa - usuário será criado quando necessário
        } else if (mongoUser == null) {
          // Se email não confirmado E usuário não existe, mostrar tela de verificação
          print('[OnboardingOrchestrator] Usuário não existe e email não confirmado - mostrando tela de verificação');
          return OnboardingState.emailNotVerified;
        }
      }
    
    // 4. Verificar se precisa autenticar com passkey
    // Se o usuário tem passkeys configuradas mas ainda não autenticou com passkey nesta sessão
    if (kIsWeb && _passkeyService.isSupported) {
      try {
        // Verificar se há passkeys registradas para este usuário
        final passkeys = await _passkeyService.listPasskeys().timeout(
          const Duration(seconds: 2),
          onTimeout: () => <Map<String, dynamic>>[],
        );
        
        if (passkeys.isNotEmpty) {
          // Usuário tem passkeys configuradas
          // Verificar se já autenticou com passkey nesta sessão
          final prefs = await SharedPreferences.getInstance();
          final hasAuthenticatedWithPasskey = prefs.getBool('passkey_authenticated_${currentUser.id}') ?? false;
          
          if (!hasAuthenticatedWithPasskey) {
            // Usuário tem passkeys mas ainda não autenticou com passkey nesta sessão
            print('[OnboardingOrchestrator] Usuário tem passkeys mas não autenticou ainda - mostrando tela de passkey');
            return OnboardingState.passkeyNotVerified;
          }
        }
      } catch (e) {
        // Se houver erro ao verificar passkeys, continuar normalmente
        print('[OnboardingOrchestrator] Erro ao verificar passkeys: $e');
      }
    }
    
    // 5. Verificar se tem foto de perfil
    // NOTA: Foto de perfil é opcional - não bloqueia o onboarding
    // Se mongoUser for null, assumir que não tem foto (mas não bloquear)
    final hasProfilePicture = mongoUser != null && 
                             mongoUser.profilePictureUrl != null && 
                             mongoUser.profilePictureUrl!.isNotEmpty;
    
    // Se não tem foto, verificar se o usuário já passou pela tela de foto e escolheu pular
    if (!hasProfilePicture) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final hasSkippedPhoto = prefs.getBool('onboarding_photo_skipped_${currentUser.id}') ?? false;
        
        // Se o usuário já escolheu pular a foto, não mostrar a tela novamente
        if (hasSkippedPhoto) {
          print('[OnboardingOrchestrator] Usuário já pulou a foto - não mostrar tela novamente');
          // Continuar para próxima etapa
        } else {
          // Só mostrar tela de foto se a conta foi criada recentemente (últimos 10 minutos)
          final createdAt = currentUser.createdAt;
          final createdStr = createdAt.toString();
          final createdDateTime = DateTime.parse(createdStr);
          final now = DateTime.now();
          final minutesSinceCreation = now.difference(createdDateTime).inMinutes;
          
          // Só exigir foto se a conta foi criada há menos de 10 minutos
          if (minutesSinceCreation < 10) {
            return OnboardingState.needsProfilePicture;
          }
          // Se passou mais de 10 minutos, assumir que já teve oportunidade
        }
      } catch (e) {
        // Se não conseguir verificar, não bloquear - permitir continuar
        print('[OnboardingOrchestrator] Erro ao verificar foto: $e');
      }
    }
    
    // 6. Verificar se precisa selecionar wallet
    final activeWalletId = await _walletStorageService.getActiveWalletId().timeout(
      const Duration(seconds: 2),
      onTimeout: () => null,
    );
    
    if (activeWalletId == null) {
      // Verificar se há wallets disponíveis
      try {
        final wallets = await _walletService.getAllWallets().timeout(
          const Duration(seconds: 3),
          onTimeout: () => <Wallet>[],
        );
        
        // Se houver apenas uma wallet, selecionar automaticamente
        if (wallets.length == 1) {
          await _walletStorageService.setActiveWalletId(wallets.first.id);
          return OnboardingState.completed;
        }
        
        // Se houver múltiplas wallets, precisa selecionar
        if (wallets.length > 1) {
          return OnboardingState.needsWalletSelection;
        }
        
        // Se não houver wallets, criar uma e selecionar automaticamente
        final newWallet = await _walletService.createWallet();
        await _walletStorageService.setActiveWalletId(newWallet.id);
        return OnboardingState.completed;
      } catch (e) {
        // Em caso de erro, assumir que precisa selecionar wallet
        return OnboardingState.needsWalletSelection;
      }
    }
    
    // Tudo completo!
    return OnboardingState.completed;
    } catch (e, stackTrace) {
      // Capturar qualquer erro não tratado
      print('[OnboardingOrchestrator] Erro não capturado: $e');
      print('[OnboardingOrchestrator] Stack trace: $stackTrace');
      
      // Em caso de erro, verificar se usuário está autenticado
      final isAuthenticated = _authService.isAuthenticated;
      final currentUser = _authService.currentUser;
      
      if (!isAuthenticated || currentUser == null) {
        return OnboardingState.notAuthenticated;
      }
      
      // Se autenticado mas erro, verificar se email está realmente verificado
      // Se não conseguir verificar, ir para login para evitar loops
      try {
        final emailConfirmed = currentUser.emailConfirmedAt != null;
        if (emailConfirmed) {
          // Email confirmado - tentar continuar para completed
          return OnboardingState.completed;
        }
        
        // Verificar se usuário existe no MongoDB como alternativa
        final mongoUser = await _userService.getCurrentUser(forceRefresh: false).timeout(
          const Duration(seconds: 1),
          onTimeout: () => null,
        );
        
        if (mongoUser != null) {
          // Usuário existe - tentar continuar para completed
          return OnboardingState.completed;
        }
        
        // Se email não confirmado e usuário não existe, só então mostrar tela de verificação
        // currentUser já foi verificado acima, então está garantido que não é null
        return OnboardingState.emailNotVerified;
      } catch (e2) {
        // Se houver erro ao verificar, ir para login para evitar loops
        print('[OnboardingOrchestrator] Erro ao verificar fallback: $e2');
      }
      
      // Em caso de erro, sempre ir para login
      return OnboardingState.notAuthenticated;
    }
  }
  
  /// Verifica se o usuário completou o onboarding básico (autenticação + email + foto)
  /// Útil para saber se pode pular etapas opcionais
  Future<bool> hasCompletedBasicOnboarding() async {
    final state = await getCurrentState();
    return state == OnboardingState.completed || 
           state == OnboardingState.needsWalletSelection;
  }
  
  /// Marca a foto de perfil como pulada (para evitar loops)
  /// Isso deve ser chamado quando o usuário escolhe pular a foto
  Future<void> markProfilePictureAsSkipped() async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('onboarding_photo_skipped_${currentUser.id}', true);
        print('[OnboardingOrchestrator] Foto marcada como pulada para usuário ${currentUser.id}');
      }
    } catch (e) {
      print('[OnboardingOrchestrator] Erro ao marcar foto como pulada: $e');
    }
  }
}

