import 'dart:typed_data';
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
  final _storageService = StorageService();
  
  bool _isLoading = false;
  bool _isLoginMode = true; // true = login, false = signup
  bool _obscurePassword = true;
  String? _inviteTokenFromUrl;
  Uint8List? _selectedProfilePicture;
  bool _isUploadingPicture = false;

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

  // Selecionar foto de perfil
  Future<void> _selectProfilePicture() async {
    try {
      setState(() {
        _isUploadingPicture = true;
      });

      final imageBytes = await _storageService.pickImage();
      
      if (imageBytes != null) {
        setState(() {
          _selectedProfilePicture = imageBytes;
          _isUploadingPicture = false;
        });
      } else {
        setState(() {
          _isUploadingPicture = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploadingPicture = false;
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
              // Verificar se o usuário existe no MongoDB, se não, criar
              try {
                final existingUser = await _userService.getCurrentUser();
                if (existingUser == null) {
                  // Usuário não existe no MongoDB, verificar se há nome guardado do registro
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
                  
                  // Criar ou atualizar usuário no MongoDB com o nome correto
                  // Se o usuário já foi criado automaticamente pelo backend, isso vai atualizar o nome
                  await _userService.createOrUpdateUser(userName);
                  
                  // Atualizar Display Name no Supabase também
                  try {
                    await _authService.updateDisplayName(userName);
                  } catch (e) {
                    // Display Name é menos crítico
                  }
                  
                  // Forçar refresh do cache e verificar se o nome está correto
                  final createdUser = await _userService.getCurrentUser(forceRefresh: true);
                  if (createdUser != null && createdUser.name != userName) {
                    // Se o nome ainda estiver errado, tentar atualizar novamente
                    await _userService.createOrUpdateUser(userName);
                    await _authService.updateDisplayName(userName);
                    await _userService.getCurrentUser(forceRefresh: true);
                  }
                  
                  // Se houver foto pendente, fazer upload agora
                  if (pendingProfilePictureBase64 != null) {
                    try {
                      // Decodificar foto base64 e fazer upload
                      final imageBytes = base64Decode(pendingProfilePictureBase64);
                      final profilePictureUrl = await _storageService.uploadProfilePicture(imageBytes);
                      // Atualizar perfil com a URL da foto
                      await _userService.updateProfilePicture(profilePictureUrl);
                      // Limpar foto pendente após sucesso
                      await prefs.remove('pending_profile_picture');
                      await prefs.remove('pending_profile_picture_url');
                    } catch (e) {
                      // Se falhar, guardar erro mas continuar - foto pode ser adicionada depois
                      // Manter a foto pendente para tentar novamente depois
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Aviso: Não foi possível fazer upload da foto. Você pode adicioná-la depois no perfil.'),
                            backgroundColor: Colors.orange,
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      }
                    }
                  } else if (pendingProfilePictureUrl != null) {
                    // Se já houver URL da foto, apenas atualizar o perfil
                    try {
                      await _userService.updateProfilePicture(pendingProfilePictureUrl);
                      await prefs.remove('pending_profile_picture');
                      await prefs.remove('pending_profile_picture_url');
                    } catch (e) {
                      // Se falhar, continuar mesmo assim
                    }
                  }
                }
              } catch (e) {
                // Se falhar ao criar usuário, tentar novamente após um delay
                // Isso pode acontecer se houver problemas de concorrência ou estados inconsistentes
                try {
                  await Future.delayed(const Duration(milliseconds: 500));
                  final retryUser = await _userService.getCurrentUser();
                  if (retryUser == null) {
                    // Se ainda não existir, criar com nome correto
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
                    
                    await _userService.createOrUpdateUser(userName);
                    
                    // Atualizar Display Name no Supabase também
                    try {
                      await _authService.updateDisplayName(userName);
                    } catch (e) {
                      // Display Name é menos crítico
                    }
                    
                    // Forçar refresh do cache
                    await _userService.getCurrentUser(forceRefresh: true);
                  } else {
                    // Se o usuário já existe mas o nome está errado, atualizar
                    final prefs = await SharedPreferences.getInstance();
                    final pendingName = prefs.getString('pending_user_name');
                    final pendingEmail = prefs.getString('pending_user_email');
                    final currentEmail = response.user!.email ?? '';
                    
                    if (pendingName != null && 
                        pendingEmail != null && 
                        pendingEmail == currentEmail &&
                        retryUser.name != pendingName) {
                      // Nome está diferente, atualizar
                      await _userService.createOrUpdateUser(pendingName);
                      await _authService.updateDisplayName(pendingName);
                      await _userService.getCurrentUser(forceRefresh: true);
                    }
                  }
                } catch (retryError) {
                  // Se ainda falhar, continuar mesmo assim - o usuário pode ser criado depois
                  // Não bloquear o login por causa disso
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
            // Guardar o nome do usuário e foto em SharedPreferences para usar após verificação de email
            // NÃO fazer upload agora porque vamos fazer logout logo depois
            // A foto será enviada quando o usuário fizer login pela primeira vez após verificar o email
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('pending_user_name', userName);
              await prefs.setString('pending_user_email', _emailController.text.trim());
              if (_selectedProfilePicture != null) {
                // Guardar foto como base64 para fazer upload depois da verificação de email
                final base64Image = base64Encode(_selectedProfilePicture!);
                await prefs.setString('pending_profile_picture', base64Image);
              }
            } catch (e) {
              // Ignorar erro - não crítico
            }
            
            // Criar usuário no MongoDB com o nome (se houver sessão temporária)
            // Nota: Se não houver sessão, o usuário será criado quando fizer login pela primeira vez
            if (session != null) {
              try {
                // Atualizar Display Name no Supabase primeiro
                try {
                  await _authService.updateDisplayName(userName);
                } catch (e) {
                  // Log mas não bloquear - Display Name é menos crítico

                }
                
                // Criar usuário no MongoDB enquanto temos sessão ativa
                // Se falhar, mostrar erro e não permitir continuar
                await _userService.createOrUpdateUser(userName);
              } catch (e) {
                // Se falhar ao criar no MongoDB, mostrar erro e não permitir continuar
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao criar conta no servidor: ${e.toString()}'),
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
              // Fazer logout para garantir estado limpo (usuário precisa verificar email)
              await _authService.signOut();
            } else {
              // Se não houver sessão, ainda tentar atualizar Display Name se possível
              // (pode não funcionar sem sessão, mas tentamos)
              try {
                await _authService.updateDisplayName(userName);
              } catch (e) {
                // Ignorar - sem sessão não podemos atualizar
              }
            }
            
            // Sempre navegar para tela de verificação quando criar conta
            // A tela de verificação vai verificar se o email já foi confirmado
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => EmailVerificationScreen(
                  email: _emailController.text.trim(),
                  inviteToken: _effectiveInviteToken,
                ),
              ),
            );
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
                    
                    // Foto de perfil (apenas no signup)
                    if (!_isLoginMode) ...[
                      Center(
                        child: GestureDetector(
                          onTap: _isUploadingPicture ? null : _selectProfilePicture,
                          child: Stack(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.primaryColor.withOpacity(0.3),
                                    width: 2,
                                  ),
                                ),
                                child: _isUploadingPicture
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : _selectedProfilePicture != null
                                        ? ClipOval(
                                            child: Image.memory(
                                              _selectedProfilePicture!,
                                              width: 100,
                                              height: 100,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : Icon(
                                            Icons.person,
                                            size: 60,
                                            color: AppTheme.primaryColor,
                                          ),
                              ),
                              if (_selectedProfilePicture != null && !_isUploadingPicture)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedProfilePicture = null;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.expenseRed,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppTheme.white,
                                          width: 2,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 16,
                                        color: AppTheme.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton.icon(
                          onPressed: _isUploadingPicture ? null : _selectProfilePicture,
                          icon: const Icon(Icons.camera_alt, size: 18),
                          label: Text(
                            _selectedProfilePicture != null
                                ? 'Alterar foto'
                                : 'Adicionar foto (opcional)',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    
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
