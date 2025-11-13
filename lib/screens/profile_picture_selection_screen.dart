import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';
import '../services/onboarding_orchestrator.dart';
import '../theme/app_theme.dart';
import 'email_verification_screen.dart';
import '../main.dart';

class ProfilePictureSelectionScreen extends StatefulWidget {
  final String email;
  final String? inviteToken;
  
  const ProfilePictureSelectionScreen({
    super.key,
    required this.email,
    this.inviteToken,
  });

  @override
  State<ProfilePictureSelectionScreen> createState() => _ProfilePictureSelectionScreenState();
}

class _ProfilePictureSelectionScreenState extends State<ProfilePictureSelectionScreen> {
  final _storageService = StorageService();
  final _userService = UserService();
  final _authService = AuthService();
  final _onboardingOrchestrator = OnboardingOrchestrator();
  
  Uint8List? _selectedProfilePicture;
  bool _isUploading = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    print('[ProfilePictureScreen] ========== TELA INICIALIZADA ==========');
    print('[ProfilePictureScreen] Email: ${widget.email}');
    print('[ProfilePictureScreen] User autenticado: ${_authService.isAuthenticated}');
    print('[ProfilePictureScreen] UserId: ${_authService.currentUserId}');
    
    // Verificar estado de autenticação e email
    final currentUser = _authService.currentUser;
    if (currentUser != null) {
      print('[ProfilePictureScreen] Email do usuário: ${currentUser.email}');
      print('[ProfilePictureScreen] Email confirmado? ${currentUser.emailConfirmedAt != null}');
      print('[ProfilePictureScreen] EmailConfirmedAt: ${currentUser.emailConfirmedAt}');
    } else {
      print('[ProfilePictureScreen] Nenhum usuário autenticado');
    }
    print('[ProfilePictureScreen] ======================================');
  }

  @override
  Widget build(BuildContext context) {
    print('[ProfilePictureSelectionScreen] Build chamado');
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            // Não permitir voltar - o usuário já criou a conta
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Não é possível voltar. A conta já foi criada.'),
                backgroundColor: AppTheme.expenseRed,
              ),
            );
          },
        ),
        title: const Text(
          'Foto de Perfil',
          style: TextStyle(color: Colors.black),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Adicione uma foto de perfil',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Você pode adicionar uma foto agora ou pular esta etapa',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              
              // Avatar/Foto
              GestureDetector(
                onTap: _isUploading ? null : _selectProfilePicture,
                child: Stack(
                  children: [
                    Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[200],
                        border: Border.all(
                          color: Colors.grey[300]!,
                          width: 2,
                        ),
                      ),
                      child: _isUploading
                          ? const Center(
                              child: CircularProgressIndicator(),
                            )
                          : _selectedProfilePicture != null
                              ? ClipOval(
                                  child: Image.memory(
                                    _selectedProfilePicture!,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.person,
                                      size: 60,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.add,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Adicionar',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                    ),
                    if (_selectedProfilePicture != null && !_isUploading)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              
              const SizedBox(height: 48),
              
              // Botão Continuar (só habilitado se houver foto selecionada)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isLoading || _isUploading || _selectedProfilePicture == null) 
                      ? null 
                      : _handleContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          'Continuar',
                          style: TextStyle(
                            color: _selectedProfilePicture == null ? Colors.grey[600] : Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Botão Pular
              TextButton(
                onPressed: _isLoading || _isUploading ? null : _handleSkip,
                child: const Text(
                  'Pular esta etapa',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectProfilePicture() async {
    try {
      print('[ProfilePictureScreen] Selecionando foto...');
      setState(() {
        _isUploading = true;
      });

      final imageBytes = await _storageService.pickImage();
      print('[ProfilePictureScreen] Foto selecionada? ${imageBytes != null}');
      
      if (imageBytes != null) {
        print('[ProfilePictureScreen] Tamanho da foto selecionada: ${imageBytes.lengthInBytes} bytes');
        setState(() {
          _selectedProfilePicture = imageBytes;
          _isUploading = false;
        });
        print('[ProfilePictureScreen] Foto guardada no estado. _selectedProfilePicture não é null? ${_selectedProfilePicture != null}');
      } else {
        print('[ProfilePictureScreen] Nenhuma foto foi selecionada');
        setState(() {
          _isUploading = false;
        });
      }
    } catch (e) {
      print('[ProfilePictureScreen] ERRO ao selecionar foto: $e');
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar foto: $e'),
            backgroundColor: AppTheme.expenseRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _handleContinue() async {
    print('[ProfilePictureScreen] _handleContinue chamado');
    print('[ProfilePictureScreen] Foto selecionada? ${_selectedProfilePicture != null}');
    if (_selectedProfilePicture != null) {
      print('[ProfilePictureScreen] Tamanho da foto: ${_selectedProfilePicture!.lengthInBytes} bytes');
    }
    
    if (_selectedProfilePicture == null) {
      // Se não houver foto, marcar que o usuário pulou esta etapa
      // Isso evita loops infinitos
      print('[ProfilePictureScreen] Nenhuma foto selecionada - usuário pulou esta etapa');
      print('[ProfilePictureScreen] Marcando foto como pulada no orquestrador...');
      
      // Marcar no orquestrador que o usuário pulou a foto
      await _onboardingOrchestrator.markProfilePictureAsSkipped();
      
      // Aguardar um pouco para garantir que o estado foi atualizado
      await Future.delayed(const Duration(milliseconds: 300));
      
      print('[ProfilePictureScreen] Navegando para AuthWrapper...');
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const AuthWrapper(),
          ),
          (route) => false,
        );
      }
      return;
    }

    print('[ProfilePictureScreen] Iniciando processo de upload...');
    setState(() => _isLoading = true);

    try {
      // Verificar que o token está disponível
      final accessToken = _authService.currentAccessToken;
      print('[ProfilePictureScreen] Token disponível? ${accessToken != null}');
      if (accessToken == null) {
        throw Exception('Token de acesso não disponível');
      }

      print('[ProfilePictureScreen] Iniciando upload da foto para Supabase Storage...');
      
      // Fazer upload da foto para o Supabase Storage
      final uploadedProfilePictureUrl = await _storageService.uploadProfilePicture(_selectedProfilePicture!);
      print('[ProfilePictureScreen] Upload concluído. URL: $uploadedProfilePictureUrl');
      
      // Salvar o link da foto no MongoDB
      print('[ProfilePictureScreen] Salvando URL no MongoDB...');
      await _userService.updateProfilePicture(uploadedProfilePictureUrl);
      print('[ProfilePictureScreen] Requisição de salvar URL enviada ao MongoDB');
      
      // Verificar que foi salvo
      print('[ProfilePictureScreen] Aguardando processamento do MongoDB...');
      await Future.delayed(const Duration(milliseconds: 500));
      print('[ProfilePictureScreen] Verificando se foi salvo...');
      final userWithPhoto = await _userService.getCurrentUser(forceRefresh: true);
      print('[ProfilePictureScreen] Usuário obtido: ${userWithPhoto != null}');
      
      if (userWithPhoto != null) {
        print('[ProfilePictureScreen] URL salva no usuário: ${userWithPhoto.profilePictureUrl}');
        print('[ProfilePictureScreen] URL esperada: $uploadedProfilePictureUrl');
        print('[ProfilePictureScreen] URLs coincidem? ${userWithPhoto.profilePictureUrl == uploadedProfilePictureUrl}');
      }
      
      if (userWithPhoto != null && userWithPhoto.profilePictureUrl == uploadedProfilePictureUrl) {
        print('[ProfilePictureScreen] ✅ Foto salva e verificada com sucesso!');
        print('[ProfilePictureScreen] Navegando após upload bem-sucedido...');
        _navigateToEmailVerification();
        return; // Garantir que não continue após navegar
      } else {
        // Tentar novamente
        print('[ProfilePictureScreen] ⚠️ Foto não foi salva corretamente. Tentando novamente...');
        await _userService.updateProfilePicture(uploadedProfilePictureUrl);
        await Future.delayed(const Duration(milliseconds: 500));
        final retryUser = await _userService.getCurrentUser(forceRefresh: true);
        
        if (retryUser != null && retryUser.profilePictureUrl == uploadedProfilePictureUrl) {
          print('[ProfilePictureScreen] ✅ Foto salva após retry!');
          print('[ProfilePictureScreen] Navegando após retry bem-sucedido...');
          _navigateToEmailVerification();
          return; // Garantir que não continue após navegar
        } else {
          print('[ProfilePictureScreen] ❌ ERRO: Foto não foi salva mesmo após retry');
          throw Exception('Não foi possível salvar a foto no servidor');
        }
      }
      
    } catch (e, stackTrace) {
      print('[ProfilePictureScreen] ❌ ERRO ao fazer upload: $e');
      print('[ProfilePictureScreen] Stack trace: $stackTrace');
      print('[ProfilePictureScreen] ERRO ao fazer upload: $e');
      
      if (mounted) {
        setState(() => _isLoading = false);
        
        final errorString = e.toString().toLowerCase();
        final isSizeError = errorString.contains('tamanho') || 
                           errorString.contains('size') ||
                           errorString.contains('too large') ||
                           errorString.contains('muito grande') ||
                           (_selectedProfilePicture != null && _selectedProfilePicture!.lengthInBytes > 5 * 1024 * 1024);
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Erro ao salvar foto'),
              content: Text(
                isSizeError
                  ? 'A foto selecionada é muito grande. Por favor, escolha uma foto menor (máximo 5MB).'
                  : 'Não foi possível salvar a foto: ${e.toString()}. Você pode tentar novamente ou continuar sem foto.'
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Tentar novamente
                    _handleContinue();
                  },
                  child: const Text('Tentar Novamente'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Continuar sem foto
                    _navigateToEmailVerification();
                  },
                  child: const Text('Continuar Sem Foto'),
                ),
              ],
            );
          },
        );
      }
    }
  }

  Future<void> _handleSkip() async {
    _navigateToEmailVerification();
  }

  Future<void> _navigateToEmailVerification() async {
    print('[ProfilePictureScreen] ========== Navegando após foto ==========');
    
    // Usar o orquestrador para determinar o próximo passo
    try {
      final state = await _onboardingOrchestrator.getCurrentState();
      print('[ProfilePictureScreen] Estado após foto: $state');
      
      if (mounted) {
        // Sempre navegar para AuthWrapper - ele vai determinar o próximo passo baseado no estado
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const AuthWrapper(),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      print('[ProfilePictureScreen] Erro ao verificar estado: $e');
      // Em caso de erro, fazer logout e ir para verificação de email
      try {
        await _authService.signOut();
      } catch (_) {}
      
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => EmailVerificationScreen(
              email: widget.email,
              inviteToken: widget.inviteToken,
            ),
          ),
        );
      }
    }
  }
}

