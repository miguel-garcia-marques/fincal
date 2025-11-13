import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/wallet_storage_service.dart';
import '../services/wallet_service.dart';
import '../models/wallet.dart';

/// Estado do processo de onboarding do usuário
enum OnboardingState {
  /// Usuário não está autenticado
  notAuthenticated,
  
  /// Email não foi verificado
  emailNotVerified,
  
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
  
  OnboardingOrchestrator({
    AuthService? authService,
    UserService? userService,
    WalletStorageService? walletStorageService,
    WalletService? walletService,
  }) : _authService = authService ?? AuthService(),
       _userService = userService ?? UserService(),
       _walletStorageService = walletStorageService ?? WalletStorageService(),
       _walletService = walletService ?? WalletService();

  /// Determina o estado atual do onboarding do usuário
  /// Retorna o próximo passo necessário ou completed se tudo estiver ok
  Future<OnboardingState> getCurrentState() async {
    // 1. Verificar autenticação
    final isAuthenticated = _authService.isAuthenticated;
    final currentUser = _authService.currentUser;
    
    if (!isAuthenticated || currentUser == null) {
      return OnboardingState.notAuthenticated;
    }
    
    // 2. Verificar se email foi confirmado
    final emailConfirmed = currentUser.emailConfirmedAt != null;
    if (!emailConfirmed) {
      return OnboardingState.emailNotVerified;
    }
    
    // 3. Verificar se usuário existe no MongoDB
    final mongoUser = await _userService.getCurrentUser(forceRefresh: false).timeout(
      const Duration(seconds: 3),
      onTimeout: () => null,
    );
    
    if (mongoUser == null) {
      // Usuário não existe no MongoDB - ainda está no processo de criação
      return OnboardingState.emailNotVerified;
    }
    
    // 4. Verificar se tem foto de perfil
    // NOTA: Foto de perfil é opcional - não bloqueia o onboarding
    final hasProfilePicture = mongoUser.profilePictureUrl != null && 
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
    
    // 5. Verificar se precisa selecionar wallet
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

