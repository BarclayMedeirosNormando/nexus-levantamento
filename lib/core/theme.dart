import 'package:flutter/material.dart';

/// Paleta e estilos — espelha exatamente o protótipo visual já aprovado
/// (design_screens/*.dc.html: Login, Home, Escola, Ambiente etc.), pra não
/// existir divergência entre o mockup e o app de verdade.
class AppColors {
  AppColors._();

  static const bg = Color(0xFFF4F8FB);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1F2937);
  static const muted = Color(0xFF5F7185);
  static const line = Color(0xFFDBE5EE);
  static const lineStrong = Color(0xFFBCCBDA);
  static const primary = Color(0xFF2484C6);
  static const navy = Color(0xFF262B65);
  static const primarySoft = Color(0xFFE4F1FB);
  static const success = Color(0xFF0FAF5D);
  static const warning = Color(0xFFF9A826);
  static const danger = Color(0xFFED1C24);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      fontFamily: 'Inter',
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lineStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 11,
          color: Color(0xFF41536A),
          letterSpacing: 0.5,
        ),
      ),
      // Obs.: não customizamos cardTheme aqui de propósito — o nome da classe
      // (CardTheme vs CardThemeData) mudou entre versões recentes do Flutter,
      // e não dá pra confirmar qual o SDK instalado na sua máquina a partir
      // daqui. O Card() já fica razoável com o ColorScheme acima; se quiser
      // o visual arredondado/com borda exato do mockup, é só adicionar de
      // volta o cardTheme depois de confirmar a versão do Flutter instalada.
    );
  }
}
