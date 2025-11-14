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

class _AuthWrapperState extends State<AuthWrapper> {
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
    
    // Escutar mudanças de autenticação com debounce
    _authSubscription = _authService.authStateChanges.listen((AuthState state) {
      if (mounted && !_isCheckingAuth) {
        // Debounce: aguardar um pouco antes de re-verificar
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && !_isCheckingAuth) {
            _checkAuth();
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
    _authSubscription?.cancel();
    _linkSubscription?.cancel();
    super.dispose();
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
      print('[AuthWrapper] Verificando estado do onboarding...');
      final state = await _onboardingOrchestrator.getCurrentState();
      print('[AuthWrapper] Estado atual: $state');
      
      if (mounted) {
        setState(() {
          _onboardingState = state;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[AuthWrapper] Erro ao verificar onboarding: $e');
      if (mounted) {
        setState(() {
          _onboardingState = OnboardingState.notAuthenticated;
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
          // Se não autenticado mas tem sessão, mostrar tela de verificação
          try {
            final user = _authService.currentUser;
            if (user != null) {
              return EmailVerificationScreen(
                email: user.email ?? '',
                inviteToken: null,
              );
            }
          } catch (e) {
            print('[AuthWrapper] Erro ao obter usuário: $e');
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
