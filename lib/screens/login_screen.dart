import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/wallet_service.dart';
import '../services/storage_service.dart';
import '../services/passkey_service.dart';
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
  final _passkeyService = PasskeyService();
  
  bool _isLoading = false;
  bool _isLoginMode = true; // true = login, false = signup
  bool _obscurePassword = true;
  String? _inviteTokenFromUrl;
  bool _passkeySupported = false;
  bool _emailEntered = false; // Controla se email foi inserido (para mostrar senha ou passkey)
  List<String> _previousEmails = []; // Lista de emails usados anteriormente
  bool _showEmailList = false; // Controla se mostra lista de emails ou formulário

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
    
    // Carregar emails usados anteriormente e depois verificar se deve mostrar lista
    _loadPreviousEmails().then((_) {
      // Verificar se o usuário já está autenticado (após verificar email)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkIfAlreadyAuthenticated();
        _checkPasskeySupport();
        // Se houver emails anteriores e estiver no modo login, mostrar lista primeiro
        if (mounted && _previousEmails.isNotEmpty && _isLoginMode) {
          setState(() {
            _showEmailList = true;
          });
        }
      });
    });
  }

  // Carregar emails usados anteriormente do SharedPreferences
  Future<void> _loadPreviousEmails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final emailsJson = prefs.getStringList('previous_emails') ?? [];
      if (mounted) {
        setState(() {
          _previousEmails = emailsJson;
        });
      }
    } catch (e) {
      // Ignorar erros ao carregar emails anteriores
    }
  }

  // Salvar email usado anteriormente
  Future<void> _saveEmail(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final emails = prefs.getStringList('previous_emails') ?? [];
      
      // Remover email se já existir (para mover para o topo)
      emails.remove(email);
      
      // Adicionar no início da lista
      emails.insert(0, email);
      
      // Limitar a 10 emails mais recentes
      if (emails.length > 10) {
        emails.removeRange(10, emails.length);
      }
      
      await prefs.setStringList('previous_emails', emails);
      
      if (mounted) {
        setState(() {
          _previousEmails = emails;
        });
      }
    } catch (e) {
      // Ignorar erros ao salvar email
    }
  }

  // Verificar suporte a passkeys após o widget estar montado
  void _checkPasskeySupport() {
    if (kIsWeb) {
      // Tentar múltiplas vezes para garantir que o JavaScript está carregado
      _tryCheckPasskeySupport(attempt: 1);
    }
  }

  void _tryCheckPasskeySupport({int attempt = 1}) {
    if (!kIsWeb || !mounted) return;
    
    // Tentar verificar suporte
    try {
      final supported = _passkeyService.isSupported;
      print('[Passkey] Tentativa $attempt - Suporte: $supported');
      
      if (supported) {
        if (mounted) {
          setState(() {
            _passkeySupported = true;
          });
        }
        print('[Passkey] ✅ Suporte detectado!');
        return;
      }
    } catch (e) {
      print('[Passkey] Erro na verificação: $e');
    }
    
    // Se não suportado e ainda não tentamos muitas vezes, tentar novamente
    if (attempt < 5 && mounted) {
      Future.delayed(Duration(milliseconds: 300 * attempt), () {
        _tryCheckPasskeySupport(attempt: attempt + 1);
      });
    } else {
      // Após várias tentativas, verificar diretamente a API do navegador
      print('[Passkey] Tentativas esgotadas. Verificando diretamente...');
      _checkDirectWebAuthnSupport();
    }
  }

  void _checkDirectWebAuthnSupport() {
    if (!kIsWeb || !mounted) return;
    
    try {
      // Forçar verificação direta
      if (mounted) {
        setState(() {
          // Tentar verificar uma última vez
          _passkeySupported = _passkeyService.isSupported;
        });
      }
    } catch (e) {
      print('[Passkey] Erro na verificação direta: $e');
    }
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
                // Salvar email usado anteriormente
                await _saveEmail(_emailController.text.trim());
                
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
                
                // Salvar email usado anteriormente após signup bem-sucedido
                await _saveEmail(_emailController.text.trim());
                
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

  // Handler para quando usuário submete apenas o email
  Future<void> _handleEmailSubmit() async {
    if (_isLoading) return;
    
    // Validar email
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    // Mostrar campo de senha e botão de passkey (se disponível)
    setState(() {
      _emailEntered = true;
    });
  }

  // Handler para login com passkey
  Future<void> _handlePasskeyLogin() async {
    if (_isLoading) return;
    
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      // Validar email primeiro
      if (!_formKey.currentState!.validate()) {
        return;
      }
    }
    
    setState(() => _isLoading = true);

    try {
      // Autenticar com passkey
      final result = await _passkeyService.authenticateWithPasskey(email);
      
      if (mounted && result['success'] == true) {
        final userEmail = result['email'] as String?;
        final requiresPassword = result['requiresPassword'] as bool? ?? false;
        
        // Prioridade 1: Tentar usar token do magic link para criar sessão automaticamente
        final token = result['token'] as String?;
        if (token != null && token.isNotEmpty && userEmail != null) {
          try {
            // Usar verifyOTP com o token do magic link
            // Isso cria uma sessão válida com refresh_token real do Supabase
            final session = await _authService.setSessionWithToken(token, userEmail);
            
            if (session.session != null && session.user != null && mounted) {
              // Login bem-sucedido sem precisar de senha! 🎉
              // IMPORTANTE: Após login com passkey, garantir que o email seja considerado verificado
              // A passkey já valida a identidade do usuário, então não precisamos de verificação de email adicional
              try {
                // Fazer refresh da sessão para garantir que os dados estão atualizados
                await _authService.supabase.auth.refreshSession();
                
                // Marcar que o usuário tem passkeys (para evitar tela de verificação de email)
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('user_has_passkeys_${session.user!.id}', true);
                
                // Salvar email usado anteriormente
                await _saveEmail(userEmail);
              } catch (e) {
                // Ignorar erros no refresh - não crítico
              }
              
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Login com passkey bem-sucedido!'),
                  backgroundColor: AppTheme.incomeGreen,
                ),
              );
              
              // Navegar para AuthWrapper
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (context) => const AuthWrapper(),
                ),
                (route) => false,
              );
              return;
            }
          } catch (e) {
            // Log apenas do tipo de erro, sem informações sensíveis
            print('[Passkey Login] Erro ao criar sessão: ${e.runtimeType}');
            // Se falhar, tentar fallback ou mostrar campo de senha
          }
        }
        
        // Fallback: Se não tivermos token ou se falhou, tentar magic link direto
        final magicLink = result['magicLink'] as String?;
        if (magicLink != null && userEmail != null && !requiresPassword) {
          try {
            final session = await _authService.supabase.auth.verifyOTP(
              type: OtpType.magiclink,
              email: userEmail,
              token: token,
            );
            
            if (session.session != null && mounted) {
              // Fazer refresh da sessão após login bem-sucedido
              try {
                await _authService.supabase.auth.refreshSession();
              } catch (e) {
                // Ignorar erros no refresh
              }
              
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Login com passkey bem-sucedido!'),
                  backgroundColor: AppTheme.incomeGreen,
                ),
              );
              
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (context) => const AuthWrapper(),
                ),
                (route) => false,
              );
              return;
            }
          } catch (e) {
            // Log apenas do tipo de erro
            print('[Passkey Login] Erro ao usar fallback: ${e.runtimeType}');
          }
        }
        
        // Último fallback: Mostrar campo de senha
        if (userEmail != null) {
          if (mounted) {
            setState(() {
              _emailEntered = true;
            });
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(requiresPassword 
                  ? 'Autenticação com passkey verificada! Por favor, insira sua senha para completar o login.'
                  : 'Autenticação com passkey verificada! Por favor, insira sua senha para completar o login.'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        } else {
          // Se não houver email, mostrar erro
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Erro: Email não recebido'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        // Se não houver sucesso, mostrar erro
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Erro ao autenticar com passkey'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Erro ao autenticar com passkey';
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('cancelado')) {
          errorMessage = 'Autenticação cancelada';
        } else if (errorStr.contains('não encontrada')) {
          errorMessage = 'Nenhuma passkey encontrada. Por favor, registre uma passkey primeiro.';
        } else if (errorStr.contains('não suportadas')) {
          errorMessage = 'Passkeys não são suportadas neste dispositivo';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppTheme.expenseRed,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Método para selecionar um email da lista
  void _selectEmailFromList(String email) {
    setState(() {
      _emailController.text = email;
      _showEmailList = false;
      _emailEntered = true; // Mostrar campo de senha automaticamente
    });
  }

  // Método para mostrar formulário de email novo
  void _showNewEmailForm() {
    setState(() {
      _showEmailList = false;
      _emailController.clear();
    });
  }

  // Widget para mostrar lista de emails anteriores
  Widget _buildEmailList() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1400;
    
    return Column(
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
        
        // Título da lista
        Text(
          'Selecione uma conta',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isDesktop ? 20 : 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.black,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Escolha uma conta para continuar',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        SizedBox(height: 32),
        
        // Lista de emails
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _previousEmails.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: Colors.grey[300],
            ),
            itemBuilder: (context, index) {
              final email = _previousEmails[index];
              return InkWell(
                onTap: () => _selectEmailFromList(email),
                hoverColor: AppTheme.black.withOpacity(0.05),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 16.0,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.black.withOpacity(0.1),
                        ),
                        child: Icon(
                          Icons.email_outlined,
                          color: AppTheme.black.withOpacity(0.6),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              email,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.black,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Conta existente',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Colors.grey[400],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        
        SizedBox(height: 24),
        
        // Botão para usar email novo
        OutlinedButton.icon(
          onPressed: _showNewEmailForm,
          icon: const Icon(Icons.add, size: 20),
          label: const Text('Usar outro email'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: const BorderSide(color: AppTheme.black),
          ),
        ),
        
        SizedBox(height: 16),
        
        // Toggle para signup
        TextButton(
          onPressed: _isLoading
              ? null
              : () {
                  setState(() {
                    _isLoginMode = !_isLoginMode;
                    _showEmailList = false;
                    _emailEntered = false;
                    _passwordController.clear();
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
    );
  }

  // Widget para mostrar formulário de login/signup
  Widget _buildLoginForm() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1400;
    
    return Form(
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
                    
                    // Email field com autocompletar
                    Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          // Mostrar os 5 emails mais recentes quando o campo está vazio
                          return _previousEmails.take(5);
                        }
                        final query = textEditingValue.text.toLowerCase();
                        // Filtrar emails que contenham o texto digitado (case-insensitive)
                        return _previousEmails.where((email) {
                          return email.toLowerCase().contains(query);
                        }).take(10); // Aumentar para 10 sugestões quando há texto
                      },
                      onSelected: (String email) {
                        // Atualizar o controller principal quando um email é selecionado
                        _emailController.text = email;
                        // Se estiver no modo login e email foi selecionado, mostrar campo de senha
                        if (_isLoginMode && !_emailEntered) {
                          _handleEmailSubmit();
                        }
                      },
                      fieldViewBuilder: (
                        BuildContext context,
                        TextEditingController textEditingController,
                        FocusNode focusNode,
                        VoidCallback onFieldSubmitted,
                      ) {
                        // Inicializar o controller do autocomplete com o valor atual apenas uma vez
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (textEditingController.text != _emailController.text) {
                            textEditingController.text = _emailController.text;
                          }
                        });
                        
                        return TextFormField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: _isLoginMode && !_emailEntered 
                              ? TextInputAction.next 
                              : TextInputAction.done,
                          onFieldSubmitted: _isLoginMode && !_emailEntered
                              ? (_) => _handleEmailSubmit()
                              : null,
                          onChanged: (value) {
                            // Sincronizar mudanças do autocomplete para o controller principal
                            if (_emailController.text != value) {
                              _emailController.text = value;
                            }
                          },
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
                        );
                      },
                      optionsViewBuilder: (
                        BuildContext context,
                        AutocompleteOnSelected<String> onSelected,
                        Iterable<String> options,
                      ) {
                        if (options.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4.0,
                            borderRadius: BorderRadius.circular(12),
                            color: AppTheme.white,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 250),
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final String email = options.elementAt(index);
                                  return InkWell(
                                    onTap: () => onSelected(email),
                                    hoverColor: AppTheme.black.withOpacity(0.05),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0,
                                        vertical: 12.0,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.email_outlined,
                                            size: 20,
                                            color: AppTheme.black.withOpacity(0.6),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              email,
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: AppTheme.black,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Password field (apenas se email foi inserido no modo login, ou sempre no signup)
                    if (_isLoginMode && _emailEntered || !_isLoginMode) ...[
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
                    ] else if (_isLoginMode && !_emailEntered) ...[
                      // Botões de ação quando apenas email está preenchido
                      const SizedBox(height: 8),
                      
                      // Botão de continuar com email
                      ElevatedButton(
                        onPressed: _isLoading ? null : _handleEmailSubmit,
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
                            : const Text(
                                'Continuar',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Botão de passkey (se suportado)
                      if (kIsWeb && _passkeySupported) ...[
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _handlePasskeyLogin,
                          icon: const Icon(Icons.fingerprint, size: 20),
                          label: const Text('Entrar com Passkey'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: const BorderSide(color: AppTheme.black),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 16),
                    ],
                    
                    // Submit button (apenas se senha está visível)
                    if (_isLoginMode && _emailEntered || !_isLoginMode) ...[
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
                      
                      // Botão de passkey (se suportado e no modo login)
                      if (kIsWeb && _passkeySupported && _isLoginMode && _emailEntered) ...[
                        const SizedBox(height: 12),
                        const Row(
                          children: [
                            Expanded(child: Divider()),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('ou'),
                            ),
                            Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _handlePasskeyLogin,
                          icon: const Icon(Icons.fingerprint, size: 20),
                          label: const Text('Entrar com Passkey'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: const BorderSide(color: AppTheme.black),
                          ),
                        ),
                      ],
                    const SizedBox(height: 16),
                    ],
                    
                    // Botão para voltar (se email foi inserido)
                    if (_isLoginMode && _emailEntered) ...[
                      TextButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () {
                                setState(() {
                                  _emailEntered = false;
                                  _passwordController.clear();
                                });
                              },
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text('Voltar'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    
          // Toggle between login and signup
          TextButton(
            onPressed: _isLoading
                ? null
                : () {
                    setState(() {
                      _isLoginMode = !_isLoginMode;
                      _emailEntered = false; // Reset ao trocar modo
                      _passwordController.clear();
                      // Se voltar para login e houver emails, mostrar lista
                      if (_isLoginMode && _previousEmails.isNotEmpty) {
                        _showEmailList = true;
                      } else {
                        _showEmailList = false;
                      }
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
    );
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
              child: _showEmailList && _isLoginMode && _previousEmails.isNotEmpty
                  ? _buildEmailList()
                  : _buildLoginForm(),
            ),
          ),
        ),
      ),
    );
  }
}

