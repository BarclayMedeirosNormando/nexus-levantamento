import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/escolas_repository.dart';
import '../../data/local/levantamentos_repository.dart';

/// Levantamento aberto (em_andamento). Ainda um stub: DATA_INICIO e
/// LAT/LONG_ABERTURA já são capturados na abertura (feito antes de chegar
/// aqui — ver EscolaDetailScreen), mas a seleção de Ambientes (Tela 4 do
/// spec) é a próxima etapa.
class LevantamentoScreen extends StatelessWidget {
  const LevantamentoScreen({super.key, required this.escola, required this.levantamento});
  final Escola escola;
  final Levantamento levantamento;

  @override
  Widget build(BuildContext context) {
    final temGps = levantamento.latAbertura != null && levantamento.longAbertura != null;
    return Scaffold(
      appBar: AppBar(title: Text(escola.nome)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.play_circle_outline, color: AppColors.primary, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Levantamento em andamento',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _InfoRow(label: 'Aberto em', value: _formatarData(levantamento.dataInicio)),
          _InfoRow(label: 'Técnico', value: levantamento.tecnicoAbertura),
          _InfoRow(
            label: 'Localização',
            value: temGps
                ? '${levantamento.latAbertura!.toStringAsFixed(6)}, ${levantamento.longAbertura!.toStringAsFixed(6)}'
                : 'Não capturada (sem GPS/permissão no momento da abertura)',
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: const [
                Icon(Icons.construction_rounded, color: AppColors.muted, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Seleção de ambientes (com os ambientes padrão pré-marcados) chega na próxima etapa.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatarData(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(dt.day)}/${dois(dt.month)}/${dt.year} ${dois(dt.hour)}:${dois(dt.minute)}';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11,
              color: AppColors.muted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 15, color: AppColors.ink)),
        ],
      ),
    );
  }
}
