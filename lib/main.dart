import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/invite_accept_screen.dart';
import 'screens/wallet_selection_screen.dart';
import 'screens/profile_picture_selection_screen.dart';
import 'screens/email_verification_screen.dart';
import 'screens/passkey_verification_screen.dart';
import 'services/auth_service.dart';
import 'services/navigation_service.dart';
import 'services/onboarding_orchestrator.dart';
import 'theme/app_theme.dart';
import 'config/supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configurar orientação
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Tratamento de erros global
  FlutterError.onError = (FlutterErrorDetails details) {
    // Filtrar erros conhecidos do Flutter Web durante hot restart
    final exception = details.exception.toString();
    final isDisposedError = exception.contains('Trying to render a disposed EngineFlutterView') ||
                           exception.contains('isDisposed');
    final isLegacyJsError = exception.contains('LegacyJavaScriptObject') ||
                           exception.contains('DiagnosticsNode');
    
    // Ignorar erros conhecidos do Flutter Web que não afetam funcionalidade
    if (isDisposedError || isLegacyJsError) {
      // Silenciar esses erros durante hot restart no web
      return;
    }
    
    FlutterError.presentError(details);
  };

  // Tratamento de erros assíncronos
  PlatformDispatcher.instance.onError = (error, stack) {
    // Filtrar erros conhecidos do Flutter Web
    final errorStr = error.toString();
    final isDisposedError = errorStr.contains('Trying to render a disposed EngineFlutterView') ||
                           errorStr.contains('isDisposed');
    final isLegacyJsError = errorStr.contains('LegacyJavaScriptObject') ||
                           errorStr.contains('DiagnosticsNode');
    
    // Ignorar erros conhecidos do Flutter Web
    if (isDisposedError || isLegacyJsError) {
      return true; // Erro tratado
    }
    
    // Logar outros erros assíncronos para debug
    print('ERRO ASSÍNCRONO NÃO TRATADO: $error');
    print('Stack trace: $stack');
    
    // Retornar true para evitar que o erro seja propagado e cause crash
    // Mas logamos para debug
    return true;
  };

  try {
    // Inicializar Supabase
    // As credenciais vêm de SupabaseConfig ou de --dart-define
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
  } catch (e) {
    // Continuar mesmo com erro para ver o que acontece
  }

  runApp(const FinCalApp());
}

class FinCalApp extends StatelessWidget {
  const FinCalApp({super.key});

  // Detectar rota inicial baseada na URL
  static String? _getInitialRoute() {
    if (!kIsWeb) return null;
    
    final uri = Uri.base;
    
    // Verificar query parameter ?token=xxx
    final token = uri.queryParameters['token'];
    if (token != null && token.isNotEmpty) {
      return '/invite?token=$token';
    }
    
    // Verificar path /invite/token
    if (uri.path.startsWith('/invite/')) {
      return uri.path;
    }
    
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FinCal',
      debugShowCheckedModeBanner: false,
      navigatorKey: NavigationService.navigatorKey,
      builder: (context, child) {
        // Garantir que MediaQuery está disponível e recalcular tema
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery,
          child: Theme(
            data: AppTheme.lightTheme(context, mediaQuery.size.width),
            child: child!,
          ),
        );
      },
      theme: AppTheme.lightTheme(context, 375.0), // Tema inicial padrão
      onGenerateRoute: (settings) {
        // Detectar URLs de invite
        if (kIsWeb) {
          final uri = Uri.parse(settings.name ?? Uri.base.toString());
          
          // Verificar query parameter ?token=xxx
          final token = uri.queryParameters['token'];
          if (token != null && token.isNotEmpty) {
            return MaterialPageRoute(
              builder: (context) => InviteAcceptScreen(token: token),
              settings: settings,
            );
          }
          
          // Verificar path /invite/token
          if (uri.path.startsWith('/invite/')) {
            final pathParts = uri.path.split('/');
            if (pathParts.length >= 3 && pathParts[2].isNotEmpty) {
              final inviteToken = pathParts[2];
              return MaterialPageRoute(
                builder: (context) => InviteAcceptScreen(token: inviteToken),
                settings: settings,
              );
            }
          }
        }
        
        // Rota padrão
        return MaterialPageRoute(
          builder: (context) => const AuthWrapper(),
          settings: settings,
        );
      },
      initialRoute: kIsWeb ? _getInitialRoute() : null,
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  final _authService = AuthService();
  final _onboardingOrchestrator = OnboardingOrchestrator();
  
  bool _isLoading = true;
  OnboardingState _onboardingState = OnboardingState.notAuthenticated;
  bool _isCheckingAuth = false; // Flag para prevenir chamadas simultâneas

  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<Uri>? _linkSubscription;
  AppLinks? _appLinks;

  @override
  void initState() {
    super.initState();
    // Registrar observer para detectar quando app volta ao foreground
    WidgetsBinding.instance.addObserver(this);
    // Inicializar app_links para deep linking (não-web apenas)
    if (!kIsWeb) {
      _appLinks = AppLinks();
      _initDeepLinks();
    }
    
    // Timeout de segurança para garantir que o loading sempre termine
    Timer(const Duration(seconds: 10), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    });
    
    // Verificar autenticação e invite (já chama _checkAuth internamente)
    _checkAuthAndInvite();
    
    // Escutar mudanças de autenticação com debounce mais longo
    // Não verificar imediatamente - apenas quando realmente necessário
    // Isso previne interrupções durante operações do usuário
    _authSubscription = _authService.authStateChanges.listen((AuthState state) {
      if (mounted && !_isCheckingAuth) {
        // Debounce mais longo: aguardar 3 segundos antes de re-verificar
        // Isso dá tempo para operações do usuário completarem
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && !_isCheckingAuth) {
            // Só verificar se realmente houve uma mudança significativa
            // Se o usuário ainda está autenticado, não precisa verificar novamente
            if (state.event == AuthChangeEvent.signedOut || 
                state.event == AuthChangeEvent.tokenRefreshed) {
              _checkAuth();
            }
          }
        });
      }
    });
  }

  // Inicializar deep links para apps nativos
  void _initDeepLinks() {
    if (_appLinks == null) return;
    
    // Obter link inicial se o app foi aberto por um link
    _appLinks!.getInitialLink().then((Uri? uri) {
      if (uri != null) {
        _handleDeepLink(uri);
      }
    });
    
    // Escutar links enquanto o app está em execução
    _linkSubscription = _appLinks!.uriLinkStream.listen(
      (Uri uri) {
        _handleDeepLink(uri);
      },
      onError: (Object err) {
        // Ignorar erros de deep linking
      },
    );
  }

  // Processar deep link
  void _handleDeepLink(Uri uri) {
    if (!mounted) return;
    
    // Extrair token do invite da URL
    String? inviteToken;
    
    // Verificar query parameter ?token=xxx
    inviteToken = uri.queryParameters['token'];
    
    // Verificar path /invite/token
    if (inviteToken == null && uri.path.startsWith('/invite/')) {
      final pathParts = uri.path.split('/');
      if (pathParts.length >= 3 && pathParts[2].isNotEmpty) {
        inviteToken = pathParts[2];
      }
    }
    
    // Se houver token, navegar para a tela de invite
    if (inviteToken != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final isAuthenticated = _onboardingState != OnboardingState.notAuthenticated;
          if (!isAuthenticated) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => LoginScreen(inviteToken: inviteToken),
              ),
            );
          } else {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => InviteAcceptScreen(token: inviteToken!),
              ),
            );
          }
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Quando o app volta ao foreground (resumed), verificar se a sessão ainda é válida
    if (state == AppLifecycleState.resumed) {
      print('[AuthWrapper] App voltou ao foreground - verificando sessão...');
      _verifySessionOnResume();
    }
  }

  /// Verifica se a sessão ainda é válida quando o app volta ao foreground
  /// Se a sessão expirou, redireciona imediatamente para login
  /// MAS só se realmente necessário - não interrompe operações ativas
  Future<void> _verifySessionOnResume() async {
    // Prevenir chamadas simultâneas
    if (_isCheckingAuth) {
      return;
    }

    // Só verificar se o usuário estava autenticado antes
    if (_onboardingState == OnboardingState.notAuthenticated) {
      return;
    }

    try {
      // Verificar se a sessão ainda é válida SEM fazer refresh forçado
      // Isso previne interrupções por erros de rede transitórios
      final isSessionValid = await _authService.isSessionValid(forceRefresh: false).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          // Timeout não significa necessariamente que está inválida
          // Pode ser erro de rede - verificar se ainda temos sessão local
          final hasSession = _authService.isAuthenticated;
          print('[AuthWrapper] Timeout ao verificar sessão - mantendo sessão local: $hasSession');
          return hasSession; // Manter sessão se ainda existe localmente
        },
      );

      if (!isSessionValid) {
        // Verificar novamente com refresh forçado antes de deslogar
        // Isso previne deslogar por erros transitórios
        print('[AuthWrapper] Sessão pode ter expirado - verificando novamente com refresh...');
        final isValidAfterRefresh = await _authService.isSessionValid(forceRefresh: true).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            // Se timeout no refresh também, verificar se ainda temos sessão local
            return _authService.isAuthenticated;
          },
        );
        
        if (!isValidAfterRefresh) {
          print('[AuthWrapper] Sessão realmente expirada - redirecionando para login');
          
          // Sessão expirada - fazer logout e redirecionar para login
          if (mounted) {
            // Fazer logout silencioso (sem mostrar erros)
            try {
              await _authService.signOut();
            } catch (e) {
              // Ignorar erros no logout - o importante é redirecionar
              print('[AuthWrapper] Erro ao fazer logout: $e');
            }

            // Atualizar estado para forçar redirecionamento para login
            if (mounted) {
              setState(() {
                _onboardingState = OnboardingState.notAuthenticated;
                _isLoading = false;
              });
            }
          }
        } else {
          print('[AuthWrapper] Sessão válida após refresh');
        }
      } else {
        print('[AuthWrapper] Sessão ainda válida');
        // Não fazer refresh automático - só quando necessário
      }
    } catch (e) {
      print('[AuthWrapper] Erro ao verificar sessão no resume: $e');
      // Em caso de erro, não assumir imediatamente que está inválida
      // Pode ser erro de rede transitório - manter sessão se ainda existe
      if (!_authService.isAuthenticated) {
        // Só verificar novamente se realmente não há sessão
        _checkAuth();
      }
    }
  }

  Future<void> _checkAuthAndInvite() async {
    await _checkAuth();
    
    // Verificar se há um invite na URL após verificar autenticação
    if (kIsWeb && mounted) {
      final uri = Uri.base;
      String? inviteToken;
      
      // Verificar query parameter ?token=xxx
      final token = uri.queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        inviteToken = token;
      }
      
      // Verificar path /invite/token
      if (inviteToken == null && uri.path.startsWith('/invite/')) {
        final pathParts = uri.path.split('/');
        if (pathParts.length >= 3 && pathParts[2].isNotEmpty) {
          inviteToken = pathParts[2];
        }
      }
      
      // Se houver invite token, navegar para a tela de invite
      if (inviteToken != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            // Se não estiver autenticado, redirecionar para login com token
            final isAuthenticated = _onboardingState != OnboardingState.notAuthenticated;
            if (!isAuthenticated) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => LoginScreen(inviteToken: inviteToken),
                ),
              );
            } else {
              // Se estiver autenticado, ir direto para a tela de invite
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => InviteAcceptScreen(token: inviteToken!),
                ),
              );
            }
          }
        });
      }
    }
  }

  /// Verifica o estado do onboarding usando o orquestrador
  Future<void> _checkAuth() async {
    // Prevenir chamadas simultâneas
    if (_isCheckingAuth) {
      return;
    }
    
    _isCheckingAuth = true;
    try {
      // PRIMEIRO: Verificar se há uma sessão e se ela ainda é válida
      // Isso previne que o usuário use a app com sessão expirada
      // MAS não fazer refresh forçado para evitar interrupções
      if (_authService.isAuthenticated) {
        final isSessionValid = await _authService.isSessionValid(forceRefresh: false).timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            // Timeout não significa necessariamente inválida - pode ser erro de rede
            // Se ainda temos sessão local, considerar válida
            return _authService.isAuthenticated;
          },
        );
        
        if (!isSessionValid) {
          // Verificar novamente com refresh antes de deslogar
          // Isso previne deslogar por erros transitórios
          print('[AuthWrapper] Sessão pode ter expirado - verificando novamente...');
          final isValidAfterRefresh = await _authService.isSessionValid(forceRefresh: true).timeout(
            const Duration(seconds: 3),
            onTimeout: () => _authService.isAuthenticated, // Manter se ainda existe localmente
          );
          
          if (!isValidAfterRefresh) {
            print('[AuthWrapper] Sessão realmente expirada na verificação inicial - redirecionando para login');
            // Sessão expirada - fazer logout e redirecionar para login
            try {
              await _authService.signOut();
            } catch (e) {
              // Ignorar erros no logout
              print('[AuthWrapper] Erro ao fazer logout: $e');
            }
            
            if (mounted) {
              setState(() {
                _onboardingState = OnboardingState.notAuthenticated;
                _isLoading = false;
              });
            }
            return;
          }
        }
      }
      
      print('[AuthWrapper] Verificando estado do onboarding...');
      final state = await _onboardingOrchestrator.getCurrentState().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('[AuthWrapper] Timeout ao verificar estado do onboarding');
          // Em caso de timeout, verificar se está autenticado e email confirmado
          final isAuthenticated = _authService.isAuthenticated;
          final currentUser = _authService.currentUser;
          
          if (isAuthenticated && currentUser != null) {
            final emailConfirmed = currentUser.emailConfirmedAt != null;
            if (emailConfirmed) {
              // Email confirmado - tentar continuar
              return OnboardingState.completed;
            } else {
              // Email não confirmado - mostrar tela de verificação
              return OnboardingState.emailNotVerified;
            }
          }
          
          // Não autenticado - ir para login
          return OnboardingState.notAuthenticated;
        },
      );
      print('[AuthWrapper] Estado atual: $state');
      
      if (mounted) {
        setState(() {
          _onboardingState = state;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      print('[AuthWrapper] Erro ao verificar onboarding: $e');
      print('[AuthWrapper] Stack trace: $stackTrace');
      
      // Em caso de erro, verificar estado básico de autenticação
      final isAuthenticated = _authService.isAuthenticated;
      final currentUser = _authService.currentUser;
      
      if (mounted) {
        setState(() {
          // Se houver erro, sempre ir para login para evitar loops
          // Só mostrar tela de verificação se realmente conseguir verificar que email não está verificado
          if (isAuthenticated && currentUser != null) {
            // Tentar verificar se email está confirmado
            final emailConfirmed = currentUser.emailConfirmedAt != null;
            if (emailConfirmed) {
              // Email confirmado - tentar continuar
              _onboardingState = OnboardingState.completed;
            } else {
              // Email não confirmado - mostrar tela de verificação
              _onboardingState = OnboardingState.emailNotVerified;
            }
          } else {
            // Não autenticado - ir para login
            _onboardingState = OnboardingState.notAuthenticated;
          }
          _isLoading = false;
        });
      }
    } finally {
      _isCheckingAuth = false;
    }
  }


  @override
  Widget build(BuildContext context) {
    // Tratar erros durante o build
    try {
      if (_isLoading) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }

      // Navegar baseado no estado do onboarding
      switch (_onboardingState) {
        case OnboardingState.notAuthenticated:
          return const LoginScreen();
          
        case OnboardingState.emailNotVerified:
          // Só mostrar tela de verificação se realmente houver usuário autenticado
          // e o email não estiver verificado
          try {
            final isAuthenticated = _authService.isAuthenticated;
            final user = _authService.currentUser;
            
            // Verificar se realmente está autenticado e tem usuário
            if (!isAuthenticated || user == null) {
              print('[AuthWrapper] Não autenticado - redirecionando para login');
              return const LoginScreen();
            }
            
            // Verificar se o email realmente não está verificado
            final emailConfirmed = user.emailConfirmedAt != null;
            if (emailConfirmed) {
              // Email já está verificado - recarregar estado
              print('[AuthWrapper] Email já verificado - recarregando estado');
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _checkAuth();
                }
              });
              return const LoginScreen();
            }
            
            // Só mostrar tela de verificação se email realmente não estiver verificado
            print('[AuthWrapper] Mostrando tela de verificação para ${user.email}');
              return EmailVerificationScreen(
                email: user.email ?? '',
                inviteToken: null,
              );
          } catch (e) {
            print('[AuthWrapper] Erro ao verificar estado de verificação: $e');
            // Em caso de erro, sempre ir para login
            return const LoginScreen();
          }
          
        case OnboardingState.passkeyNotVerified:
          // Usuário tem passkeys mas precisa autenticar com passkey
          try {
            final user = _authService.currentUser;
            if (user != null) {
              return PasskeyVerificationScreen(
                email: user.email ?? '',
              );
            }
          } catch (e) {
            print('[AuthWrapper] Erro ao obter usuário para passkey: $e');
          }
          return const LoginScreen();
          
        case OnboardingState.needsProfilePicture:
          try {
            final user = _authService.currentUser;
            return ProfilePictureSelectionScreen(
              email: user?.email ?? '',
              inviteToken: null,
            );
          } catch (e) {
            print('[AuthWrapper] Erro ao construir ProfilePictureSelectionScreen: $e');
            return const LoginScreen();
          }
          
        case OnboardingState.needsWalletSelection:
          return const WalletSelectionScreen();
          
        case OnboardingState.completed:
          return const HomeScreen();
      }
    } catch (e, stackTrace) {
      // Capturar qualquer erro durante o build
      print('[AuthWrapper] Erro durante build: $e');
      print('[AuthWrapper] Stack trace: $stackTrace');
      
      // Retornar uma tela de erro segura
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text('Erro ao carregar aplicativo'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  // Tentar recarregar
                  _checkAuth();
                },
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
  }
}
