import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/theme.dart';

/// Tela cheia de leitura de código de barras/QR (2026-09-12) — usada pelo
/// botão de câmera ao lado do campo Tombamento em
/// `equipamento_form_screen.dart`. Devolve o primeiro código lido
/// (`Navigator.pop(codigo)`) assim que detecta algo, sem confirmação manual
/// de propósito — é rápido em campo, e se ler errado o técnico só edita o
/// campo de texto normalmente depois.
///
/// Plugin mobile-only (Android/iOS) — não roda no build desktop atual (ver
/// mesmo caveat em `equipamento_form_screen.dart`).
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  bool _lido = false;

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
          MobileScanner(onDetect: _onDetect),
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
