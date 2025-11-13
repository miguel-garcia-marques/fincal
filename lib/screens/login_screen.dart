import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/wallet_service.dart';
import '../services/storage_service.dart';
import '../utils/responsive_fonts.dart';
import '../theme/app_theme.dart';
import '../main.dart';
import 'email_verification_screen.dart';
import 'invite_accept_screen.dart';
import 'profile_picture_selection_screen.dart';

class LoginScreen extends StatefulWidget {
  final String? inviteToken;
  
  const LoginScreen({super.key, this.inviteToken});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _authService = AuthService();
  final _userService = UserService();
  
  bool _isLoading = false;
  bool _isLoginMode = true; // true = login, false = signup
  bool _obscurePassword = true;
  String? _inviteTokenFromUrl;

  @override
  void initState() {
    super.initState();
    // Verificar se há inviteToken na URL (para casos onde o usuário volta para login)
    if (kIsWeb) {
      final uri = Uri.base;
      final token = uri.queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        _inviteTokenFromUrl = token;
      }
    }
    
    // Verificar se o usuário já está autenticado (após verificar email)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfAlreadyAuthenticated();
    });
  }

  Future<void> _checkIfAlreadyAuthenticated() async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser != null && currentUser.emailConfirmedAt != null) {
        // Usuário já está autenticado e email confirmado
        // Fazer refresh da sessão para garantir que o AuthWrapper detecte
        await _authService.supabase.auth.refreshSession();
        // O AuthWrapper vai detectar a mudança e redirecionar para home
      }
    } catch (e) {
      // Ignorar erros - não crítico
    }
  }

  // Getter para obter o inviteToken (prioriza o da URL, depois o do widget)
  String? get _effectiveInviteToken {
    return _inviteTokenFromUrl ?? widget.inviteToken;
  }



  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    // Prevenir múltiplos cliques
    if (_isLoading) {
      return;
    }
    
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isLoading = true);

    try {
      if (_isLoginMode) {
        // Se houver inviteToken e usuário já estiver autenticado com outra conta,
        // fazer logout primeiro para evitar conflitos
        if (_effectiveInviteToken != null && _authService.isAuthenticated) {
          try {
            await _authService.signOut();
            // Aguardar um pouco para garantir que o logout foi processado
            await Future.delayed(const Duration(milliseconds: 300));
          } catch (e) {
            // Ignorar erros no logout - continuar mesmo assim
          }
        }
        
        AuthResponse response;
        try {
          response = await _authService.signInWithEmail(
            _emailController.text.trim(),
            _passwordController.text,
          );
        } catch (e) {
          // Verificar se o erro é relacionado a email não confirmado
          final errorString = e.toString().toLowerCase();
          
          if (errorString.contains('email not confirmed') || 
              errorString.contains('email_not_confirmed') ||
              errorString.contains('email not verified') ||
              errorString.contains('email_not_verified')) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Por favor, verifique seu email antes de fazer login.'),
                  backgroundColor: AppTheme.expenseRed,
                  duration: Duration(seconds: 4),
                ),
              );
              setState(() => _isLoading = false);
            }
            return;
          }
          // Re-lançar outros erros
          rethrow;
        }
        
        // Verificar se o login foi bem-sucedido
        if (mounted) {
          if (response.user != null && response.session != null) {
            // Verificar se o email foi confirmado
            if (response.user!.emailConfirmedAt == null) {
              // Email não verificado
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Por favor, verifique seu email antes de fazer login.'),
                    backgroundColor: AppTheme.expenseRed,
                    duration: Duration(seconds: 4),
                  ),
                );
                setState(() => _isLoading = false);
              }
              return;
            } else {
              // Login bem-sucedido e email verificado
              // GARANTIR que o usuário existe no MongoDB e Supabase com as mesmas informações
              // NÃO permitir acesso até que ambos estejam sincronizados
              try {
                final existingUser = await _userService.getCurrentUser();
                if (existingUser == null) {
                  // Usuário não existe no MongoDB, criar agora com sincronização completa
                  final prefs = await SharedPreferences.getInstance();
                  final pendingName = prefs.getString('pending_user_name');
                  final pendingEmail = prefs.getString('pending_user_email');
                  final pendingProfilePictureBase64 = prefs.getString('pending_profile_picture');
                  final pendingProfilePictureUrl = prefs.getString('pending_profile_picture_url');
                  final currentEmail = response.user!.email ?? '';
                  
                  String userName;
                  if (pendingName != null && 
                      pendingEmail != null && 
                      pendingEmail == currentEmail) {
                    // Usar o nome guardado do registro
                    userName = pendingName;
                    // Limpar o nome guardado após usar
                    await prefs.remove('pending_user_name');
                    await prefs.remove('pending_user_email');
                  } else {
                    // Usar email como nome temporário
                    userName = currentEmail.split('@')[0];
                  }
                  
                  // 1. Atualizar Display Name no Supabase PRIMEIRO
                  await _authService.updateDisplayName(userName);
                  
                  // 2. Criar usuário no MongoDB com o mesmo nome
                  await _userService.createOrUpdateUser(userName);
                  
                  // 3. Verificar que o usuário foi criado com sucesso
                  final createdUser = await _userService.getCurrentUser(forceRefresh: true);
                  if (createdUser == null) {
                    throw Exception('Falha ao criar usuário no servidor');
                  }
                  
                  // 4. Verificar que o nome está sincronizado em ambos os sistemas
                  if (createdUser.name != userName) {
                    // Tentar corrigir sincronização
                    await _userService.createOrUpdateUser(userName);
                    await _authService.updateDisplayName(userName);
                    // Verificar novamente
                    final recheckUser = await _userService.getCurrentUser(forceRefresh: true);
                    if (recheckUser == null || recheckUser.name != userName) {
                      throw Exception('Falha ao sincronizar informações do usuário');
                    }
                  }
                  
                  // Se houver foto pendente, fazer upload agora
                  // Tentar salvar de forma robusta com retries
                  if (pendingProfilePictureBase64 != null) {
                    try {
                      print('Encontrada foto pendente. Fazendo upload...');
                      // Decodificar foto base64 e fazer upload
                      final imageBytes = base64Decode(pendingProfilePictureBase64);
                      final storageService = StorageService();
                      final profilePictureUrl = await storageService.uploadProfilePicture(imageBytes);
                      print('Upload da foto pendente concluído. URL: $profilePictureUrl');
                      
                      // Atualizar perfil com a URL da foto
                      await _userService.updateProfilePicture(profilePictureUrl);
                      
                      // Verificar que foi salvo
                      await Future.delayed(const Duration(milliseconds: 300));
                      final userWithPhoto = await _userService.getCurrentUser(forceRefresh: true);
                      if (userWithPhoto != null && userWithPhoto.profilePictureUrl == profilePictureUrl) {
                        // Limpar foto pendente após sucesso confirmado
                        await prefs.remove('pending_profile_picture');
                        await prefs.remove('pending_profile_picture_url');
                        print('Foto pendente salva e verificada com sucesso');
                      } else {
                        // Tentar novamente se não foi salvo
                        print('Foto não foi salva. Tentando novamente...');
                        await _userService.updateProfilePicture(profilePictureUrl);
                        await Future.delayed(const Duration(milliseconds: 300));
                        final retryUser = await _userService.getCurrentUser(forceRefresh: true);
                        if (retryUser != null && retryUser.profilePictureUrl == profilePictureUrl) {
                          await prefs.remove('pending_profile_picture');
                          await prefs.remove('pending_profile_picture_url');
                          print('Foto pendente salva após retry');
                        } else {
                          throw Exception('Não foi possível salvar foto pendente após tentativas');
                        }
                      }
                    } catch (e) {
                      // Se falhar, guardar erro mas continuar - foto pode ser adicionada depois
                      // Manter a foto pendente para tentar novamente depois
                      print('ERRO ao fazer upload da foto pendente: $e');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Aviso: Não foi possível fazer upload da foto pendente. Você pode adicioná-la depois no perfil.'),
                            backgroundColor: Colors.orange,
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      }
                    }
                  } else if (pendingProfilePictureUrl != null) {
                    // Se já houver URL da foto, apenas atualizar o perfil
                    try {
                      print('Encontrada URL de foto pendente. Atualizando perfil...');
                      await _userService.updateProfilePicture(pendingProfilePictureUrl);
                      await Future.delayed(const Duration(milliseconds: 300));
                      final userWithPhoto = await _userService.getCurrentUser(forceRefresh: true);
                      if (userWithPhoto != null && userWithPhoto.profilePictureUrl == pendingProfilePictureUrl) {
                        await prefs.remove('pending_profile_picture');
                        await prefs.remove('pending_profile_picture_url');
                        print('URL de foto pendente salva com sucesso');
                      }
                    } catch (e) {
                      print('ERRO ao salvar URL de foto pendente: $e');
                      // Se falhar, continuar mesmo assim - não crítico
                    }
                  }
                }
              } catch (e) {
                // Se falhar ao criar usuário, tentar novamente após um delay
                // NÃO permitir acesso até que o usuário seja criado com sucesso
                try {
                  await Future.delayed(const Duration(milliseconds: 500));
                  final retryUser = await _userService.getCurrentUser(forceRefresh: true);
                  if (retryUser == null) {
                    // Se ainda não existir, criar com nome correto e sincronização completa
                    final prefs = await SharedPreferences.getInstance();
                    final pendingName = prefs.getString('pending_user_name');
                    final pendingEmail = prefs.getString('pending_user_email');
                    final currentEmail = response.user!.email ?? '';
                    
                    String userName;
                    if (pendingName != null && 
                        pendingEmail != null && 
                        pendingEmail == currentEmail) {
                      userName = pendingName;
                    } else {
                      userName = currentEmail.split('@')[0];
                    }
                    
                    // 1. Atualizar Display Name no Supabase
                    await _authService.updateDisplayName(userName);
                    
                    // 2. Criar usuário no MongoDB
                    await _userService.createOrUpdateUser(userName);
                    
                    // 3. Verificar que foi criado com sucesso
                    final createdUser = await _userService.getCurrentUser(forceRefresh: true);
                    if (createdUser == null) {
                      throw Exception('Falha ao criar usuário no servidor após retry');
                    }
                    
                    // 4. Verificar sincronização
                    if (createdUser.name != userName) {
                      await _userService.createOrUpdateUser(userName);
                      await _authService.updateDisplayName(userName);
                      final recheckUser = await _userService.getCurrentUser(forceRefresh: true);
                      if (recheckUser == null || recheckUser.name != userName) {
                        throw Exception('Falha ao sincronizar informações do usuário após retry');
                      }
                    }
                  } else {
                    // Se o usuário já existe mas o nome está errado, atualizar com sincronização
                    final prefs = await SharedPreferences.getInstance();
                    final pendingName = prefs.getString('pending_user_name');
                    final pendingEmail = prefs.getString('pending_user_email');
                    final currentEmail = response.user!.email ?? '';
                    
                    if (pendingName != null && 
                        pendingEmail != null && 
                        pendingEmail == currentEmail &&
                        retryUser.name != pendingName) {
                      // Nome está diferente, atualizar em ambos os sistemas
                      await _userService.createOrUpdateUser(pendingName);
                      await _authService.updateDisplayName(pendingName);
                      final recheckUser = await _userService.getCurrentUser(forceRefresh: true);
                      if (recheckUser == null || recheckUser.name != pendingName) {
                        throw Exception('Falha ao sincronizar nome do usuário após retry');
                      }
                    }
                  }
                } catch (retryError) {
                  // Se ainda falhar após retry, NÃO permitir acesso
                  // Fazer logout e mostrar erro
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao criar usuário: ${retryError.toString()}. Por favor, tente novamente.'),
                        backgroundColor: AppTheme.expenseRed,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                    setState(() => _isLoading = false);
                    
                    // Fazer logout para garantir estado limpo
                    try {
                      await _authService.signOut();
                    } catch (_) {
                      // Ignorar erro no logout
                    }
                  }
                  return;
                }
              }
              
              // Se houver inviteToken, aceitar automaticamente ou redirecionar
              final inviteToken = _effectiveInviteToken;
              if (inviteToken != null && mounted) {
                // Tentar aceitar automaticamente o invite
                try {
                  final walletService = WalletService();
                  await walletService.acceptInvite(inviteToken);
                  
                  // Se aceitou com sucesso, mostrar mensagem e navegar para AuthWrapper
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Convite aceito com sucesso!'),
                        backgroundColor: AppTheme.incomeGreen,
                        duration: Duration(seconds: 2),
                      ),
                    );
                    
                    // Forçar refresh da sessão para garantir que está atualizada
                    try {
                      await _authService.supabase.auth.refreshSession();
                    } catch (_) {
                      // Ignorar erros no refresh
                    }
                    
                    // Aguardar um pouco para mostrar a mensagem e depois navegar
                    await Future.delayed(const Duration(milliseconds: 500));
                    
                    if (mounted) {
                      // Navegar para AuthWrapper que vai detectar a autenticação
                      // e redirecionar para a tela apropriada (home ou wallet selection)
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (context) => const AuthWrapper(),
                        ),
                        (route) => false, // Remove todas as rotas anteriores
                      );
                    }
                  }
                  return;
                } catch (e) {
                  // Se falhar ao aceitar automaticamente, redirecionar para tela de invite
                  // (pode ser que o invite já tenha sido aceito ou tenha algum problema)
                  if (mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => InviteAcceptScreen(token: inviteToken),
                      ),
                      (route) => false,
                    );
                  }
                  return;
                }
              }
              
              // Forçar refresh da sessão para garantir que está atualizada
              try {
                await _authService.supabase.auth.refreshSession();
              } catch (e) {
                // Ignorar erros no refresh - não crítico
              }
              
              // Verificar novamente se o usuário está autenticado antes de navegar
              final currentUser = _authService.currentUser;
              final isAuthenticated = _authService.isAuthenticated;
              final emailConfirmed = currentUser?.emailConfirmedAt != null;
              
              if (mounted && isAuthenticated && currentUser != null && emailConfirmed) {
                // Navegar de volta para o AuthWrapper que vai detectar a autenticação
                // e redirecionar para a tela apropriada (home ou wallet selection)
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => const AuthWrapper(),
                  ),
                  (route) => false, // Remove todas as rotas anteriores
                );
              } else {
                // Se por algum motivo o estado não estiver correto, aguardar um pouco e tentar novamente
                await Future.delayed(const Duration(milliseconds: 500));
                
                final retryUser = _authService.currentUser;
                final retryAuthenticated = _authService.isAuthenticated;
                final retryEmailConfirmed = retryUser?.emailConfirmedAt != null;
                
                if (mounted && retryAuthenticated && retryUser != null && retryEmailConfirmed) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const AuthWrapper(),
                    ),
                    (route) => false,
                  );
                } else {
                  // Se ainda não funcionar, mostrar erro
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Erro ao fazer login. Tente novamente.'),
                        backgroundColor: AppTheme.expenseRed,
                      ),
                    );
                    setState(() => _isLoading = false);
                  }
                }
              }
            }
          } else {
            // Login falhou sem erro explícito
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Erro ao fazer login. Verifique suas credenciais.'),
                  backgroundColor: AppTheme.expenseRed,
                ),
              );
              setState(() => _isLoading = false);
            }
          }
        }
      } else {
        final userName = _nameController.text.trim();
        final response = await _authService.signUpWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
          displayName: userName,
        );
        
        if (mounted) {
          final user = response.user;
          final session = response.session;
          
          if (user != null) {
            // Guardar o nome do usuário em SharedPreferences para usar após verificação de email (se não houver sessão)
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('pending_user_name', userName);
              await prefs.setString('pending_user_email', _emailController.text.trim());
            } catch (e) {
              // Ignorar erro - não crítico
            }
            
            // PASSO 1: Criar conta no Supabase e MongoDB
            // Neste passo apenas criamos a conta, SEM foto
            if (session != null) {
              bool supabaseFailed = false;
              bool mongoFailed = false;
              
              try {
                // PASSO 1.1: Atualizar Display Name no Supabase
                print('PASSO 1: Atualizando nome no Supabase...');
                await _authService.updateDisplayName(userName);
                print('Nome atualizado no Supabase com sucesso');
                
                // PASSO 1.2: Criar usuário no MongoDB
                print('PASSO 1: Criando usuário no MongoDB...');
                await _userService.createOrUpdateUser(userName);
                
                // Verificar que o usuário foi criado com sucesso no MongoDB
                final createdUser = await _userService.getCurrentUser(forceRefresh: true);
                if (createdUser == null) {
                  throw Exception('Falha ao verificar criação do usuário no servidor');
                }
                
                // Verificar que o nome está correto em ambos os sistemas
                if (createdUser.name != userName) {
                  // Tentar corrigir
                  await _userService.createOrUpdateUser(userName);
                  await _authService.updateDisplayName(userName);
                  // Verificar novamente
                  final recheckUser = await _userService.getCurrentUser(forceRefresh: true);
                  if (recheckUser == null || recheckUser.name != userName) {
                    throw Exception('Falha ao sincronizar informações do usuário');
                  }
                }
                print('PASSO 1: Usuário criado no MongoDB com sucesso');
                
                // PASSO 1 concluído com sucesso - navegar para tela de seleção de foto
                print('PASSO 1: Navegando para ProfilePictureSelectionScreen...');
                if (mounted) {
                  setState(() => _isLoading = false);
                  print('PASSO 1: Estado atualizado, iniciando navegação...');
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) {
                        print('PASSO 1: Construindo ProfilePictureSelectionScreen...');
                        return ProfilePictureSelectionScreen(
                          email: _emailController.text.trim(),
                          inviteToken: _effectiveInviteToken,
                        );
                      },
                    ),
                  );
                  print('PASSO 1: Navegação concluída');
                } else {
                  print('PASSO 1: ERRO - Widget não está montado, não é possível navegar');
                }
                
              } catch (e, stackTrace) {
                // Erro no Supabase ou MongoDB - falha crítica
                print('ERRO CRÍTICO no Supabase ou MongoDB: $e');
                print('Stack trace: $stackTrace');
                
                final errorString = e.toString().toLowerCase();
                if (errorString.contains('supabase') || 
                    errorString.contains('auth') ||
                    errorString.contains('token') ||
                    errorString.contains('signup')) {
                  supabaseFailed = true;
                } else {
                  mongoFailed = true;
                }
                
                // Fazer logout e mostrar form novamente
                if (mounted) {
                  try {
                    await _authService.signOut();
                  } catch (logoutError) {
                    print('Aviso: Erro ao fazer logout: $logoutError');
                  }
                  
                  setState(() => _isLoading = false);
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        supabaseFailed 
                          ? 'Erro ao criar conta no Supabase. Por favor, tente novamente.'
                          : mongoFailed
                            ? 'Erro ao criar conta no servidor (MongoDB). Por favor, tente novamente.'
                            : 'Erro ao criar conta. Por favor, tente novamente.'
                      ),
                      backgroundColor: AppTheme.expenseRed,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
                return;
              }
            } else {
              // Se não houver sessão, não podemos criar no MongoDB agora
              // O usuário será criado quando fizer login pela primeira vez após verificar email
              // Mas guardamos as informações para garantir sincronização depois
              
              // Navegar para tela de verificação (sem sessão, não há nada para salvar agora)
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => EmailVerificationScreen(
                      email: _emailController.text.trim(),
                      inviteToken: _effectiveInviteToken,
                    ),
                  ),
                );
              }
            }
          } else {
            // Erro ao criar usuário, mas não lançou exceção
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Erro ao criar conta. Tente novamente.'),
                backgroundColor: AppTheme.expenseRed,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Erro desconhecido';
        
        // Tratar erros específicos do Supabase
        final errorString = e.toString().toLowerCase();
        if (errorString.contains('email not confirmed') || 
            errorString.contains('email_not_confirmed') ||
            errorString.contains('email not verified')) {
          errorMessage = 'Por favor, verifique seu email antes de fazer login.';
        } else if (errorString.contains('invalid') || errorString.contains('credentials')) {
          errorMessage = 'Email ou senha incorretos.';
        } else if (errorString.contains('load failed') || 
                   errorString.contains('network') ||
                   errorString.contains('connection') ||
                   errorString.contains('timeout') ||
                   errorString.contains('clientexception')) {
          errorMessage = 'Erro de conexão. Verifique sua internet e tente novamente.';
        } else if (errorString.contains('authretryablefetchexception')) {
          errorMessage = 'Erro de conexão com o servidor. Tente novamente em alguns instantes.';
        } else if (_isLoginMode) {
          // Para erros de login, mostrar mensagem mais amigável
          if (errorString.contains('user not found') || errorString.contains('user_not_found')) {
            errorMessage = 'Usuário não encontrado. Verifique o email ou crie uma conta.';
          } else {
            errorMessage = 'Erro ao fazer login. Tente novamente.';
          }
        } else {
          errorMessage = 'Erro ao criar conta. Tente novamente.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppTheme.expenseRed,
            duration: const Duration(seconds: 5),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1400;
    
    return Scaffold(
      backgroundColor: AppTheme.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isDesktop ? 32.0 : 24.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isDesktop ? 450 : 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo/Título
                    Icon(
                      Icons.account_balance_wallet,
                      size: isDesktop ? 60 : 80,
                      color: AppTheme.black,
                    ),
                    SizedBox(height: isDesktop ? 16 : 24),
                    Text(
                      'FinCal',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                            fontSize: isDesktop 
                                ? ResponsiveFonts.getFontSize(context, 24)
                                : null,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.black,
                          ),
                    ),
                    SizedBox(height: isDesktop ? 32 : 48),
                    
                    // Nome field (apenas no signup)
                    if (!_isLoginMode) ...[
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Nome',
                          prefixIcon: const Icon(Icons.person),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: AppTheme.white,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Por favor, insira seu nome';
                          }
                          if (value.trim().length < 2) {
                            return 'O nome deve ter pelo menos 2 caracteres';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    
                    // Email field
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: AppTheme.white,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Por favor, insira seu email';
                        }
                        if (!value.contains('@')) {
                          return 'Por favor, insira um email válido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Password field
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: AppTheme.white,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Por favor, insira sua senha';
                        }
                        if (!_isLoginMode && value.length < 6) {
                          return 'A senha deve ter pelo menos 6 caracteres';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    
                    // Submit button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _handleSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isLoading 
                            ? AppTheme.black.withOpacity(0.5)
                            : AppTheme.black,
                        foregroundColor: AppTheme.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBackgroundColor: AppTheme.black.withOpacity(0.5),
                        disabledForegroundColor: AppTheme.white.withOpacity(0.7),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.white,
                                ),
                              ),
                            )
                          : Text(
                              _isLoginMode ? 'Entrar' : 'Criar Conta',
                              style: TextStyle(
                                fontSize: ResponsiveFonts.getFontSize(context, 16),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Toggle between login and signup
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _isLoginMode = !_isLoginMode;
                              });
                            },
                      child: Text(
                        _isLoginMode
                            ? 'Não tem uma conta? Criar conta'
                            : 'Já tem uma conta? Fazer login',
                        style: const TextStyle(color: AppTheme.black),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
