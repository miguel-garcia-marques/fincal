import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';
import 'config/supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Inicializar Supabase
  // As credenciais vêm de SupabaseConfig ou de --dart-define
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  runApp(const FinCalApp());
}

class FinCalApp extends StatelessWidget {
  const FinCalApp({super.key});

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
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
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
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return _isAuthenticated ? const HomeScreen() : const LoginScreen();
  }
}
