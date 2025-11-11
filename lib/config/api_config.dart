class ApiConfig {
  // URL do backend em produção
  // ATUALIZE ESTA URL APÓS FAZER DEPLOY NO RENDER
  static const String productionBaseUrl = 'https://seu-backend.onrender.com/api';
  
  // URL do backend em desenvolvimento
  static const String developmentBaseUrl = 'http://localhost:3000/api';
  
  // Detectar se está em produção (build release)
  static bool get isProduction {
    const isProd = bool.fromEnvironment('dart.vm.product');
    return isProd;
  }
  
  // Obter a URL base da API
  static String get baseUrl {
    // Primeiro, verifica se foi passado via --dart-define
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }
    
    // Se não, usa produção ou desenvolvimento baseado no build
    return isProduction ? productionBaseUrl : developmentBaseUrl;
  }
}

