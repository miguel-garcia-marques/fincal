import 'package:http/http.dart' as http;
import '../services/navigation_service.dart';

class ApiErrorHandler {
  // Verificar se a resposta é um erro 401 e redirecionar para login
  static Future<void> handleResponse(http.Response response) async {
    if (response.statusCode == 401) {
      // Erro 401 - não autorizado, redirecionar para login
      await NavigationService.redirectToLogin();
      throw Exception('Unauthorized - redirecionando para login');
    }
  }

  // Verificar status code e tratar 401
  static void checkStatusCode(int statusCode) {
    if (statusCode == 401) {
      // Redirecionar para login de forma assíncrona
      NavigationService.redirectToLogin();
      throw Exception('Unauthorized - redirecionando para login');
    }
  }
}

