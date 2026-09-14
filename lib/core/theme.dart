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

/// SnackBars padronizadas — ícone + cor consistentes, floating, em vez do
/// SnackBar genérico (texto em cinza) que cada tela reimplementava do seu
/// jeito. Uso: `AppSnackbar.sucesso(context, 'Salvo.')`, `.erro(...)`,
/// `.aviso(...)` (validação/atenção) ou `.info(...)` (neutro).
class AppSnackbar {
  AppSnackbar._();

  static void sucesso(BuildContext context, String mensagem) =>
      _show(context, mensagem, Icons.check_circle_outline_rounded, AppColors.success);

  static void erro(BuildContext context, String mensagem) =>
      _show(context, mensagem, Icons.error_outline_rounded, AppColors.danger);

  static void aviso(BuildContext context, String mensagem) =>
      _show(context, mensagem, Icons.info_outline_rounded, AppColors.warning);

  static void info(BuildContext context, String mensagem) =>
      _show(context, mensagem, Icons.info_outline_rounded, AppColors.primary);

  static void _show(BuildContext context, String mensagem, IconData icone, Color cor) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navy,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          content: Row(
            children: [
              Icon(icone, color: cor, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(mensagem, style: const TextStyle(color: Colors.white, fontSize: 13))),
            ],
          ),
        ),
      );
  }
}

/// Selo de status (Em andamento / Concluído) em formato de chip colorido —
/// reaproveitado em toda tela que lista levantamentos, pra não repetir o
/// mesmo Icon+Text com cores levemente diferentes em cada lugar.
class StatusLevantamentoChip extends StatelessWidget {
  const StatusLevantamentoChip({super.key, required this.concluido});
  final bool concluido;

  @override
  Widget build(BuildContext context) {
    final cor = concluido ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: cor.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(concluido ? Icons.check_circle_outline_rounded : Icons.hourglass_top_rounded, size: 14, color: cor),
          const SizedBox(width: 4),
          Text(
            concluido ? 'Concluído' : 'Em andamento',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cor),
          ),
        ],
      ),
    );
  }
}

/// Fade curto ao entrar em tela — troca o corte seco padrão do Flutter por
/// uma transição suave quando uma lista termina de carregar. Sem
/// dependência nova (`TweenAnimationBuilder` é do próprio Flutter) e roda
/// só uma vez por widget montado, então não pesa em listas grandes.
class FadeIn extends StatelessWidget {
  const FadeIn({super.key, required this.child, this.duration = const Duration(milliseconds: 220)});
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: child,
    );
  }
}

