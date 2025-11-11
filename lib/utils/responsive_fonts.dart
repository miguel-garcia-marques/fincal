import 'package:flutter/material.dart';

/// Utilitário para calcular tamanhos de fonte responsivos baseados no tamanho da tela
class ResponsiveFonts {
  /// Calcula um tamanho de fonte baseado na largura da tela
  /// 
  /// [baseSize] é o tamanho base em pixels para uma tela de referência (375px de largura)
  /// Retorna um tamanho escalado proporcionalmente ao tamanho da tela atual
  /// Usa uma progressão suave baseada em breakpoints comuns de dispositivos
  static double getFontSize(BuildContext context, double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Calcular fator de escala baseado na largura da tela
    // Usa breakpoints comuns de dispositivos para uma progressão mais natural
    // Escala mais conservadora para telas pequenas para evitar overflows
    double scaleFactor;
    
    if (screenWidth < 320) {
      // Telas muito pequenas (ex: iPhone SE antigo)
      scaleFactor = 0.65;
    } else if (screenWidth < 360) {
      // Mobile muito pequeno (320-360px)
      scaleFactor = 0.65 + ((screenWidth - 320) / 40) * 0.1; // 0.65 a 0.75
    } else if (screenWidth < 375) {
      // Mobile pequeno (360-375px)
      scaleFactor = 0.75 + ((screenWidth - 360) / 15) * 0.1; // 0.75 a 0.85
    } else if (screenWidth < 414) {
      // Mobile médio (375-414px) - tela de referência
      scaleFactor = 0.85 + ((screenWidth - 375) / 39) * 0.1; // 0.85 a 0.95
    } else if (screenWidth < 768) {
      // Mobile grande / Tablet pequeno (414-768px)
      scaleFactor = 0.95 + ((screenWidth - 414) / 354) * 0.35; // 0.95 a 1.3
    } else if (screenWidth < 1024) {
      // Tablet (768-1024px)
      scaleFactor = 1.3 + ((screenWidth - 768) / 256) * 0.2; // 1.3 a 1.5
    } else if (screenWidth < 1440) {
      // Desktop pequeno (1024-1440px)
      scaleFactor = 1.5 + ((screenWidth - 1024) / 416) * 0.2; // 1.5 a 1.7
    } else {
      // Desktop grande (> 1440px)
      scaleFactor = 1.7 + ((screenWidth - 1440).clamp(0.0, 560.0) / 560) * 0.2; // 1.7 a 1.9
      scaleFactor = scaleFactor.clamp(1.7, 1.9);
    }
    
    return baseSize * scaleFactor;
  }

  /// Calcula um tamanho de fonte baseado na altura da tela
  /// 
  /// Útil para elementos que dependem mais da altura do que da largura
  static double getFontSizeByHeight(BuildContext context, double baseSize) {
    final screenHeight = MediaQuery.of(context).size.height;
    // Tela de referência: 667px (iPhone SE / tela pequena)
    const referenceHeight = 667.0;
    
    // Calcular fator de escala baseado na altura da tela
    final scaleFactor = (screenHeight / referenceHeight).clamp(0.8, 1.5);
    
    return baseSize * scaleFactor;
  }

  /// Calcula um tamanho de fonte baseado na menor dimensão (largura ou altura)
  /// 
  /// Útil para garantir que a fonte seja legível em qualquer orientação
  static double getFontSizeByMinDimension(BuildContext context, double baseSize) {
    final size = MediaQuery.of(context).size;
    final minDimension = size.width < size.height ? size.width : size.height;
    const referenceMin = 375.0;
    
    final scaleFactor = (minDimension / referenceMin).clamp(0.8, 1.5);
    
    return baseSize * scaleFactor;
  }

  /// Calcula um tamanho de fonte com tamanho mínimo garantido
  /// 
  /// Útil para elementos pequenos que precisam permanecer legíveis mesmo em telas muito pequenas
  /// [baseSize] é o tamanho base
  /// [minSize] é o tamanho mínimo absoluto (não será menor que isso)
  static double getFontSizeWithMin(
    BuildContext context,
    double baseSize,
    double minSize,
  ) {
    final calculatedSize = getFontSize(context, baseSize);
    return calculatedSize < minSize ? minSize : calculatedSize;
  }

  /// Retorna um TextStyle com fontSize responsivo
  static TextStyle responsiveTextStyle(
    BuildContext context,
    double baseSize, {
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontSize: getFontSize(context, baseSize),
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }
}

