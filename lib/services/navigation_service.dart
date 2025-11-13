import 'package:flutter/material.dart';
import 'auth_service.dart';
import '../screens/login_screen.dart';

class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static NavigatorState? get navigator => navigatorKey.currentState;

  // Redirecionar para login quando ocorrer erro 401
  static Future<void> redirectToLogin() async {
    final navigator = NavigationService.navigator;
    if (navigator != null) {
      // Fazer logout primeiro
      final authService = AuthService();
      try {
        await authService.signOut();
      } catch (e) {
        // Continuar mesmo se o logout falhar
      }
      
      // Redirecionar para login, removendo todas as rotas anteriores
      // O Flutter vai evitar redirecionamentos desnecessários automaticamente
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }
}

