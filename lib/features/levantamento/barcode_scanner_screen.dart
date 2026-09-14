import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/theme.dart';

/// Tela cheia de leitura de código de barras/QR (2026-09-12) — usada pelos
/// botões de câmera ao lado dos campos Tombamento e Nº de Série em
/// `equipamento_form_screen.dart`. Devolve o primeiro código lido
/// (`Navigator.pop(codigo)`) assim que detecta algo, sem confirmação manual
/// de propósito — é rápido em campo, e se ler errado o técnico só edita o
/// campo de texto normalmente depois.
///
/// Plugin mobile-only (Android/iOS) — não roda no build desktop atual (ver
/// mesmo caveat em `equipamento_form_screen.dart`).
///
/// 2026-09-14: antes esta tela não tinha `errorBuilder`, então qualquer
/// falha ao abrir a câmera (permissão negada/ainda não concedida, câmera em
/// uso por outro app, etc.) caía na tela de erro padrão do mobile_scanner —
/// um ícone de alerta genérico com texto técnico em inglês, relatado em
/// campo como "aparece uma exclamação". Agora tratamos o erro explicitamente
/// e mostramos uma mensagem em português com um botão pra tentar de novo
/// (útil depois que a pessoa habilita a permissão manualmente nas
/// configurações do Android).
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  bool _lido = false;
  final MobileScannerController _controller = MobileScannerController();

  void _onDetect(BarcodeCapture capture) {
    if (_lido) return;
    final codigos = capture.barcodes;
    if (codigos.isEmpty) return;
    final valor = codigos.first.rawValue;
    if (valor == null || valor.trim().isEmpty) return;
    _lido = true;
    Navigator.of(context).pop(valor.trim());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildError(BuildContext context, MobileScannerException error, Widget? child) {
    final permissaoNegada = error.errorCode == MobileScannerErrorCode.permissionDenied;
    // 2026-09-14: primeira tentativa (remover a foto da etiqueta) não
    // resolveu — o erro persistiu mesmo sem esse fluxo antes. Enquanto não
    // sabemos a causa real, mostramos o código/mensagem técnica do
    // mobile_scanner na tela (pequeno, cinza) só pra conseguir diagnosticar
    // com print/relato de campo, já que não há acesso a log do aparelho
    // remotamente.
    final detalhe = error.errorDetails;
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.camera_alt_outlined, color: Colors.white70, size: 48),
          const SizedBox(height: 16),
          Text(
            permissaoNegada
                ? 'Permissão de câmera negada.\nVá em Configurações do Android > Apps > Nexus Levantamento > Permissões e habilite a Câmera.'
                : 'Não foi possível abrir a câmera.\nFeche outros apps que possam estar usando a câmera e tente de novo.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Text(
            'Detalhe técnico: ${error.errorCode.name}'
            '${detalhe?.code != null ? ' / ${detalhe!.code}' : ''}'
            '${detalhe?.message != null ? '\n${detalhe!.message}' : ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _controller.start(),
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: const Text('Tentar novamente', style: TextStyle(color: Colors.white)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Ler código de barras'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: _buildError,
          ),
          Center(
            child: Container(
              width: 240,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 32,
            left: 24,
            right: 24,
            child: Text(
              'Aponte a câmera pro código de barras ou QR da etiqueta',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
