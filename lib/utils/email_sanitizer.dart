/// Utilitário para sanitização e validação de emails
/// Protege contra XSS e valida formato de email
class EmailSanitizer {
  /// Sanitiza um email removendo caracteres perigosos e validando formato
  /// 
  /// Remove:
  /// - Scripts e tags HTML
  /// - Caracteres de controle
  /// - Caracteres especiais perigosos
  /// 
  /// Retorna null se o email for inválido ou contiver conteúdo perigoso
  static String? sanitize(String email) {
    if (email.isEmpty) return null;
    
    // Remover espaços no início e fim
    final trimmed = email.trim();
    
    // Validar formato básico de email
    if (!_isValidEmailFormat(trimmed)) {
      return null;
    }
    
    // Remover caracteres perigosos que poderiam ser usados em XSS
    // Mas manter caracteres válidos em emails (como +, -, _, .)
    final sanitized = _removeDangerousCharacters(trimmed);
    
    // Validar novamente após sanitização
    if (!_isValidEmailFormat(sanitized)) {
      return null;
    }
    
    // Limitar tamanho (RFC 5321: máximo 320 caracteres)
    if (sanitized.length > 320) {
      return null;
    }
    
    return sanitized.toLowerCase(); // Normalizar para lowercase
  }
  
  /// Valida formato básico de email
  static bool _isValidEmailFormat(String email) {
    // Regex básico para validar formato de email
    // Não é perfeito, mas cobre a maioria dos casos válidos
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    
    return emailRegex.hasMatch(email);
  }
  
  /// Remove caracteres perigosos que poderiam ser usados em ataques XSS
  static String _removeDangerousCharacters(String input) {
    // Lista de caracteres perigosos que não devem aparecer em emails válidos
    final dangerousChars = [
      '<', '>', '"', "'", '&', '\n', '\r', '\t',
      '\x00', '\x01', '\x02', '\x03', '\x04', '\x05', '\x06', '\x07',
      '\x08', '\x0B', '\x0C', '\x0E', '\x0F', '\x10', '\x11', '\x12',
      '\x13', '\x14', '\x15', '\x16', '\x17', '\x18', '\x19', '\x1A',
      '\x1B', '\x1C', '\x1D', '\x1E', '\x1F', '\x7F',
    ];
    
    var result = input;
    for (final char in dangerousChars) {
      result = result.replaceAll(char, '');
    }
    
    // Remover sequências que poderiam ser interpretadas como scripts
    result = result.replaceAll(RegExp(r'javascript:', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'data:', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'vbscript:', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'on\w+\s*=', caseSensitive: false), '');
    
    return result;
  }
  
  /// Valida se um email é seguro para armazenar
  /// Retorna true se o email passou todas as validações de segurança
  static bool isSafeToStore(String email) {
    final sanitized = sanitize(email);
    return sanitized != null && sanitized == email.toLowerCase().trim();
  }
}

