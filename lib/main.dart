import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/invite_accept_screen.dart';
import 'screens/wallet_selection_screen.dart';
import 'services/auth_service.dart';
import 'services/user_service.dart';
import 'services/wallet_service.dart';
import 'services/wallet_storage_service.dart';
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
    print('Flutter Error: ${details.exception}');
    print('Stack trace: ${details.stack}');
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
    
    print('Platform Error: $error');
    print('Stack trace: $stack');
    return true;
  };

  try {
    // Inicializar Supabase
    // As credenciais vêm de SupabaseConfig ou de --dart-define
    print('Inicializando Supabase...');
    print('URL: ${SupabaseConfig.supabaseUrl}');
    
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
    
    print('Supabase inicializado com sucesso');
  } catch (e, stack) {
    print('Erro ao inicializar Supabase: $e');
    print('Stack trace: $stack');
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
  final _userService = UserService();
  final _walletService = WalletService();
  final _walletStorageService = WalletStorageService();
  bool _isLoading = true;
  bool _isAuthenticated = false;
  bool _needsWalletSelection = false;

  @override
  void initState() {
    super.initState();
    _checkAuthAndInvite();
    // Escutar mudanças de autenticação
    _authService.authStateChanges.listen((AuthState state) {
      if (mounted) {
        final isAuthenticated = state.session != null;
        // Verificar se o email foi confirmado se houver usuário
        if (isAuthenticated && state.session?.user != null) {
          final emailConfirmed = state.session!.user.emailConfirmedAt != null;
          setState(() {
            _isAuthenticated = isAuthenticated && emailConfirmed;
          });
        } else {
          setState(() {
            _isAuthenticated = isAuthenticated;
          });
        }
      }
    });
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
            if (!_isAuthenticated) {
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

  Future<void> _checkAuth() async {
    final user = _authService.currentUser;
    final isAuthenticated = _authService.isAuthenticated;

    setState(() {
      // Só considerar autenticado se houver sessão E email confirmado
      if (isAuthenticated && user != null) {
        _isAuthenticated = user.emailConfirmedAt != null;
      } else {
        _isAuthenticated = false;
      }
    });

    // Se autenticado, verificar se precisa mostrar seleção de wallet
    if (_isAuthenticated) {
      await _checkWalletSelection();
    } else {
      setState(() {
      _isLoading = false;
    });
    }
  }

  Future<void> _checkWalletSelection() async {
    try {
      // Verificar se há wallet ativa salva
      final activeWalletId = await _walletStorageService.getActiveWalletId();
      
      // Se já houver wallet ativa, não precisa mostrar seleção
      if (activeWalletId != null) {
        setState(() {
          _isLoading = false;
          _needsWalletSelection = false;
        });
        return;
      }

      // Carregar dados do usuário
      final user = await _userService.getCurrentUser();
      if (user == null) {
        // Se não houver usuário, ir direto para home (será criado lá)
        setState(() {
          _isLoading = false;
          _needsWalletSelection = false;
        });
        return;
      }

      // Carregar todas as wallets
      final wallets = await _walletService.getAllWallets();
      
      // Se houver apenas uma wallet (a pessoal), usar ela automaticamente
      if (wallets.length == 1) {
        await _walletStorageService.setActiveWalletId(wallets.first.id);
        setState(() {
          _isLoading = false;
          _needsWalletSelection = false;
        });
        return;
      }

      // Se houver múltiplas wallets, mostrar tela de seleção
      setState(() {
        _isLoading = false;
        _needsWalletSelection = wallets.length > 1;
      });
    } catch (e) {
      print('Error checking wallet selection: $e');
      // Em caso de erro, ir direto para home
      setState(() {
        _isLoading = false;
        _needsWalletSelection = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAuthenticated) {
      return const LoginScreen();
    }

    // Se precisa de seleção de wallet, mostrar tela de seleção
    if (_needsWalletSelection) {
      return const WalletSelectionScreen();
    }

    // Caso contrário, mostrar home
    return const HomeScreen();
  }
}
