import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/responsive_fonts.dart';

class AppTheme {
  // Cores - Design sleek preto e branco
  static const Color pureBlack = Color(0xFF000000);
  static const Color black = Color(0xFF1A1A1A);
  static const Color darkGray = Color(0xFF2A2A2A);
  static const Color mediumGray = Color(0xFF3A3A3A);
  static const Color lightGray = Color(0xFF4A4A4A);
  static const Color lighterGray = Color(0xFF6A6A6A);
  static const Color white = Color(0xFFFFFFFF);
  static const Color offWhite = Color(0xFFF5F5F5);

  // Cores financeiras (apenas para valores)
  static const Color incomeGreen = Color(0xFF4CAF50);
  static const Color expenseRed = Color(0xFFE57373);

  // Cor primária (usando black como padrão)
  static const Color primaryColor = black;

  // Cores para categorias de orçamento
  static const Color savingsYellow = Color(0xFFFFC107); // Amarelo para poupança
  static const Color expensesRed = Color(0xFFE57373); // Vermelho para gastos
  static const Color leisureBlue = Color(0xFF81D4FA); // Azul pastel para lazer

  // Fonte monospace para valores numéricos
  static TextStyle monospaceTextStyle({
    BuildContext? context,
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
  }) {
    final responsiveFontSize = context != null
        ? ResponsiveFonts.getFontSize(context, fontSize)
        : fontSize;

    return GoogleFonts.robotoMono(
      fontSize: responsiveFontSize,
      fontWeight: fontWeight,
      color: color ?? black,
    );
  }

  static ThemeData lightTheme(BuildContext context, [double? screenWidth]) {
    // Se screenWidth não for fornecido, tentar obter do MediaQuery
    final width =
        screenWidth ?? (MediaQuery.maybeOf(context)?.size.width ?? 375.0);

    // Calcular scaleFactor com a mesma lógica do ResponsiveFonts
    double scaleFactor;

    if (width < 320) {
      // Telas muito pequenas (ex: iPhone SE antigo)
      scaleFactor = 0.65;
    } else if (width < 360) {
      // Mobile muito pequeno (320-360px)
      scaleFactor = 0.65 + ((width - 320) / 40) * 0.1; // 0.65 a 0.75
    } else if (width < 375) {
      // Mobile pequeno (360-375px)
      scaleFactor = 0.75 + ((width - 360) / 15) * 0.1; // 0.75 a 0.85
    } else if (width < 414) {
      // Mobile médio (375-414px) - tela de referência
      scaleFactor = 0.85 + ((width - 375) / 39) * 0.1; // 0.85 a 0.95
    } else if (width < 768) {
      // Mobile grande / Tablet pequeno (414-768px)
      scaleFactor = 0.95 + ((width - 414) / 354) * 0.35; // 0.95 a 1.3
    } else if (width < 1024) {
      // Tablet (768-1024px)
      scaleFactor = 1.3 + ((width - 768) / 256) * 0.2; // 1.3 a 1.5
    } else if (width < 1440) {
      // Desktop pequeno (1024-1440px)
      scaleFactor = 1.5 + ((width - 1024) / 416) * 0.2; // 1.5 a 1.7
    } else {
      // Desktop grande (> 1440px)
      scaleFactor =
          1.7 + ((width - 1440).clamp(0.0, 560.0) / 560) * 0.2; // 1.7 a 1.9
      scaleFactor = scaleFactor.clamp(1.7, 1.9);
    }
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: black,
        secondary: darkGray,
        surface: white,
        error: expenseRed,
        onPrimary: white,
        onSecondary: white,
        onSurface: black,
        onError: white,
      ),
      scaffoldBackgroundColor: offWhite,
      textTheme: GoogleFonts.spaceMonoTextTheme(
        TextTheme(
          displayLarge: TextStyle(
            fontSize: 32 * scaleFactor,
            fontWeight: FontWeight.w600,
            color: black,
            letterSpacing: -0.5,
          ),
          displayMedium: TextStyle(
            fontSize: 28 * scaleFactor,
            fontWeight: FontWeight.w600,
            color: black,
            letterSpacing: -0.5,
          ),
          displaySmall: TextStyle(
            fontSize: 24 * scaleFactor,
            fontWeight: FontWeight.w600,
            color: black,
            letterSpacing: -0.3,
          ),
          headlineMedium: TextStyle(
            fontSize: 20 * scaleFactor,
            fontWeight: FontWeight.w500,
            color: black,
            letterSpacing: -0.2,
          ),
          titleLarge: TextStyle(
            fontSize: 18 * scaleFactor,
            fontWeight: FontWeight.w500,
            color: black,
          ),
          titleMedium: TextStyle(
            fontSize: 16 * scaleFactor,
            fontWeight: FontWeight.w500,
            color: black,
          ),
          bodyLarge: TextStyle(
            fontSize: 16 * scaleFactor,
            fontWeight: FontWeight.w400,
            color: darkGray,
            height: 1.5,
          ),
          bodyMedium: TextStyle(
            fontSize: 14 * scaleFactor,
            fontWeight: FontWeight.w400,
            color: darkGray,
            height: 1.5,
          ),
          bodySmall: TextStyle(
            fontSize: 12 * scaleFactor,
            fontWeight: FontWeight.w400,
            color: darkGray,
            height: 1.4,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: black,
          foregroundColor: white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          textStyle: GoogleFonts.spaceMono(
            fontSize: 16 * scaleFactor,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.spaceMono(
            fontSize: 14 * scaleFactor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: lighterGray),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: lighterGray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: black, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      cardTheme: CardThemeData(
        color: white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          // Removido border
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        elevation: 8,
      ),
    );
  }
}
