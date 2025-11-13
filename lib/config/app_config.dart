class AppConfig {
  // URL da app em produção
  // ATUALIZE ESTA URL APÓS FAZER DEPLOY NO FIREBASE
  // Exemplo: https://seu-projeto.web.app ou https://seu-dominio.com
  static const String productionAppUrl = 'https://fincal-f7.web.app/';

  // Detectar se está em produção (build release)
  static bool get isProduction {
    const isProd = bool.fromEnvironment('dart.vm.product');
    return isProd;
  }

  // Obter a URL base da app
  static String? getAppBaseUrl() {
    // Primeiro, verifica se foi passado via --dart-define
    const envUrl = String.fromEnvironment('APP_BASE_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }

    // Se houver URL de produção configurada e estiver em produção, usar ela
    // IMPORTANTE: Em produção, sempre usar a URL configurada se disponível
    if (isProduction && productionAppUrl.isNotEmpty) {
      // Remover barra final se houver
      return productionAppUrl.endsWith('/')
          ? productionAppUrl.substring(0, productionAppUrl.length - 1)
          : productionAppUrl;
    }

    // Caso contrário, retornar null para usar a URL atual dinamicamente
    return null;
  }
}
