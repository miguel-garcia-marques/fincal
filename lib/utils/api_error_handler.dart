import 'package:http/http.dart' as http;
import '../services/navigation_service.dart';
import '../services/auth_service.dart';

class ApiErrorHandler {
  // Flag para rastrear operações críticas em andamento
  static int _criticalOperationsCount = 0;
  
  // Marcar início de operação crítica
  static void startCriticalOperation() {
    _criticalOperationsCount++;
  }
  
  // Marcar fim de operação crítica
  static void endCriticalOperation() {
    if (_criticalOperationsCount > 0) {
      _criticalOperationsCount--;
    }
  }
  
  // Verificar se há operações críticas em andamento
  static bool get hasCriticalOperations => _criticalOperationsCount > 0;
  
  // Verificar se a resposta é um erro 401 e redirecionar para login
  // MAS só se não houver operações críticas em andamento
  static Future<void> handleResponse(http.Response response) async {
    if (response.statusCode == 401) {
      // Verificar se há operações críticas em andamento
      if (hasCriticalOperations) {
        print('[ApiErrorHandler] Erro 401 durante operação crítica - tentando refresh da sessão primeiro');
        
        // Tentar fazer refresh da sessão antes de redirecionar
        try {
          final authService = AuthService();
          final isValid = await authService.isSessionValid(forceRefresh: true).timeout(
            const Duration(seconds: 3),
            onTimeout: () => false,
          );
          
          if (isValid) {
            print('[ApiErrorHandler] Sessão renovada com sucesso - não redirecionando');
            // Sessão renovada - não redirecionar, apenas relançar o erro para que a operação possa ser retentada
            throw Exception('Unauthorized - sessão renovada, tente novamente');
          }
        } catch (e) {
          print('[ApiErrorHandler] Não foi possível renovar sessão: $e');
        }
        
        // Se não conseguiu renovar, aguardar um pouco antes de redirecionar
        // Isso dá tempo para operações críticas completarem
        await Future.delayed(const Duration(seconds: 2));
        
        // Verificar novamente se ainda há operações críticas
        if (hasCriticalOperations) {
          print('[ApiErrorHandler] Ainda há operações críticas - aguardando mais tempo...');
          // Aguardar mais um pouco
          await Future.delayed(const Duration(seconds: 3));
        }
      }
      
      // Erro 401 - não autorizado, redirecionar para login
      // Mas só se não houver mais operações críticas
      if (!hasCriticalOperations) {
        await NavigationService.redirectToLogin();
      }
      throw Exception('Unauthorized - redirecionando para login');
    }
  }

  // Verificar status code e tratar 401
  static void checkStatusCode(int statusCode) {
    if (statusCode == 401) {
      // Se há operações críticas, não redirecionar imediatamente
      if (hasCriticalOperations) {
        print('[ApiErrorHandler] Erro 401 durante operação crítica - aguardando...');
        // Aguardar um pouco antes de redirecionar
        Future.delayed(const Duration(seconds: 2), () {
          if (!hasCriticalOperations) {
            NavigationService.redirectToLogin();
          }
        });
      } else {
        // Redirecionar para login de forma assíncrona
        NavigationService.redirectToLogin();
      }
      throw Exception('Unauthorized - redirecionando para login');
    }
  }
}

