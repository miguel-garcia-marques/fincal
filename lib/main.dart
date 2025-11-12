import 'dart:async';
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

  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    // Verificar autenticação imediatamente ao criar o widget
    _checkAuth();
    _checkAuthAndInvite();
    // Escutar mudanças de autenticação
    _authSubscription = _authService.authStateChanges.listen((AuthState state) {
      print('🔔 AuthWrapper: Evento de mudança de autenticação recebido');
      print('   Event type: ${state.event}');
      print('   Session: ${state.session != null}');
      if (state.session != null) {
        print('   User: ${state.session!.user.id}');
        print('   Email confirmed: ${state.session!.user.emailConfirmedAt != null}');
      }
      
      if (mounted) {
        final isAuthenticated = state.session != null;
        // Verificar se o email foi confirmado se houver usuário
        if (isAuthenticated && state.session?.user != null) {
          final emailConfirmed = state.session!.user.emailConfirmedAt != null;
          print('   ✅ Usuário autenticado e email confirmado: $emailConfirmed');
          
          if (emailConfirmed) {
            setState(() {
              _isAuthenticated = true;
              _isLoading = false;
            });
            
            // Se autenticado, verificar seleção de wallet
            print('   🔄 Verificando seleção de wallet...');
            _checkWalletSelection();
          } else {
            print('   ⚠️ Email não confirmado ainda');
            setState(() {
              _isAuthenticated = false;
              _isLoading = false;
            });
          }
        } else {
          print('   ❌ Usuário não autenticado');
          setState(() {
            _isAuthenticated = false;
            _isLoading = false;
          });
        }
      }
    });
    
    // Verificação periódica para garantir que detectamos mudanças de autenticação
    // mesmo se o stream não emitir eventos imediatamente
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      // Verificar se o estado de autenticação mudou
      final currentUser = _authService.currentUser;
      final isAuthenticated = _authService.isAuthenticated;
      final emailConfirmed = currentUser?.emailConfirmedAt != null;
      final shouldBeAuthenticated = isAuthenticated && emailConfirmed;
      
      // Log periódico (apenas a cada 2 segundos para não poluir)
      if (timer.tick % 4 == 0) {
        print('⏰ AuthWrapper: Timer polling (tick ${timer.tick})');
        print('   Estado atual: $_isAuthenticated');
        print('   Deveria ser: $shouldBeAuthenticated');
        print('   User: ${currentUser?.id}');
        print('   Email confirmed: $emailConfirmed');
      }
      
      // Se o estado mudou, atualizar
      if (shouldBeAuthenticated != _isAuthenticated) {
        print('🔄 AuthWrapper: Estado de autenticação mudou detectado via polling!');
        print('   Antes: $_isAuthenticated, Agora: $shouldBeAuthenticated');
        print('   User: ${currentUser?.id}');
        print('   Email confirmed: $emailConfirmed');
        setState(() {
          _isAuthenticated = shouldBeAuthenticated;
          _isLoading = false;
        });
        
        if (_isAuthenticated) {
          print('   ✅ Iniciando verificação de wallet...');
          _checkWalletSelection();
        }
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
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
    print('🔍 AuthWrapper: _checkAuth chamado');
    final user = _authService.currentUser;
    final isAuthenticated = _authService.isAuthenticated;
    
    print('   User: ${user?.id}');
    print('   IsAuthenticated: $isAuthenticated');
    print('   Email confirmed: ${user?.emailConfirmedAt != null}');

    final shouldBeAuthenticated = isAuthenticated && user != null && user.emailConfirmedAt != null;
    
    setState(() {
      // Só considerar autenticado se houver sessão E email confirmado
      _isAuthenticated = shouldBeAuthenticated;
      print('   Estado atualizado: _isAuthenticated = $_isAuthenticated');
    });

    // Se autenticado, verificar se precisa mostrar seleção de wallet
    if (_isAuthenticated) {
      print('   ✅ Usuário autenticado, verificando wallet...');
      await _checkWalletSelection();
    } else {
      print('   ❌ Usuário não autenticado');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkWalletSelection() async {
    print('🔍 AuthWrapper: Verificando seleção de wallet...');
    try {
      // Verificar se há wallet ativa salva
      final activeWalletId = await _walletStorageService.getActiveWalletId();
      print('   Active wallet ID: $activeWalletId');
      
      // Se já houver wallet ativa, não precisa mostrar seleção
      if (activeWalletId != null) {
        print('   ✅ Wallet ativa encontrada, indo para home');
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
      print('   📦 Carregando wallets...');
      final wallets = await _walletService.getAllWallets();
      print('   📦 Wallets encontradas: ${wallets.length}');
      
      // Se houver apenas uma wallet (a pessoal), usar ela automaticamente
      if (wallets.length == 1) {
        print('   ✅ Apenas uma wallet, usando automaticamente');
        await _walletStorageService.setActiveWalletId(wallets.first.id);
        setState(() {
          _isLoading = false;
          _needsWalletSelection = false;
        });
        return;
      }

      // Se houver múltiplas wallets, mostrar tela de seleção
      print('   📋 Múltiplas wallets, mostrando seleção');
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
    print('🏗️ AuthWrapper build:');
    print('   _isLoading: $_isLoading');
    print('   _isAuthenticated: $_isAuthenticated');
    print('   _needsWalletSelection: $_needsWalletSelection');
    print('   Current user: ${_authService.currentUser?.id}');
    print('   Email confirmed: ${_authService.currentUser?.emailConfirmedAt != null}');
    
    if (_isLoading) {
      print('   → Mostrando loading...');
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAuthenticated) {
      print('   → Mostrando LoginScreen...');
      return const LoginScreen();
    }

    // Se precisa de seleção de wallet, mostrar tela de seleção
    if (_needsWalletSelection) {
      print('   → Mostrando WalletSelectionScreen...');
      return const WalletSelectionScreen();
    }

    // Caso contrário, mostrar home
    print('   → Mostrando HomeScreen...');
    return const HomeScreen();
  }
}
