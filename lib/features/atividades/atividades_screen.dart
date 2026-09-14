import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/atividades_repository.dart';
import '../../data/local/escolas_repository.dart';

/// Tela de auditoria (ADM, 2026-09-14) — "o que cada técnico fez" em
/// adição/remoção de Ambiente, Equipamento, Inservível, Conectividade,
/// Wifi e Foto (ver AtividadesRepository e SHEET_HEADERS.ATIVIDADES no
/// backend). Lê 100% do banco local — o que já chegou neste aparelho via
/// pull_levantamentos_ativos/concluidos (que agora também trazem
/// ATIVIDADES) ou foi feito aqui mesmo. Busca/filtro são só locais, sem
/// ida ao servidor.
class AtividadesScreen extends StatefulWidget {
  const AtividadesScreen({super.key});

  @override
  State<AtividadesScreen> createState() => _AtividadesScreenState();
}

class _AtividadesScreenState extends State<AtividadesScreen> {
  final _repo = AtividadesRepository();
  final _escolasRepo = EscolasRepository();
  final _buscaController = TextEditingController();

  bool _carregando = true;
  List<AtividadeLog> _todas = const [];
  Map<String, String> _nomeEscolaPorInep = const {};
  String? _filtroTipo;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final atividades = await _repo.listarTudo();
    final escolas = await _escolasRepo.listar();
    if (!mounted) return;
    setState(() {
      _todas = atividades;
      _nomeEscolaPorInep = {for (final e in escolas) e.inep: e.nome};
      _carregando = false;
    });
  }

  List<AtividadeLog> get _filtradas {
    final termo = _buscaController.text.trim().toLowerCase();
    return _todas.where((a) {
      if (_filtroTipo != null && a.tipoEntidade != _filtroTipo) return false;
      if (termo.isEmpty) return true;
      final nomeEscola = _nomeEscolaPorInep[a.inep] ?? '';
      final campos = [a.matricula, a.nomeTecnico ?? '', a.descricao ?? '', nomeEscola, a.inep]
          .join(' ')
          .toLowerCase();
      return campos.contains(termo);
    }).toList();
  }

  String _dataFormatada(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    String dois(int v) => v.toString().padLeft(2, '0');
    return '${dois(local.day)}/${dois(local.month)}/${local.year} ${dois(local.hour)}:${dois(local.minute)}';
  }

  IconData _iconePara(String tipoEntidade) {
    switch (tipoEntidade) {
      case 'Ambiente':
        return Icons.meeting_room_outlined;
      case 'Equipamento':
        return Icons.devices_outlined;
      case 'Inservível':
        return Icons.delete_sweep_outlined;
      case 'Conectividade':
        return Icons.wifi_tethering_outlined;
      case 'Wifi':
        return Icons.wifi_outlined;
      case 'Foto':
        return Icons.photo_camera_outlined;
      default:
        return Icons.history_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final itens = _filtradas;
    return Scaffold(
      appBar: AppBar(title: const Text('Atividades')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _buscaController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar por técnico, escola ou item...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _FiltroChip(
                  label: 'Todos',
                  selecionado: _filtroTipo == null,
                  onTap: () => setState(() => _filtroTipo = null),
                ),
                for (final tipo in AtividadesRepository.tiposEntidade)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _FiltroChip(
                      label: tipo,
                      selecionado: _filtroTipo == tipo,
                      onTap: () => setState(() => _filtroTipo = tipo),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : itens.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Nenhuma atividade encontrada.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.muted),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: itens.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final a = itens[index];
                          final adicionado = a.acao == AtividadesRepository.acaoAdicionado;
                          final corAcao = adicionado ? AppColors.success : AppColors.danger;
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: corAcao.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(_iconePara(a.tipoEntidade), color: corAcao, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${a.acao} · ${a.tipoEntidade}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                      if (a.descricao != null && a.descricao!.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            a.descricao!,
                                            style: const TextStyle(fontSize: 13, color: AppColors.ink),
                                          ),
                                        ),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          '${a.nomeTecnico ?? a.matricula} · '
                                          '${_nomeEscolaPorInep[a.inep] ?? a.inep} · '
                                          '${_dataFormatada(a.criadoEm)}',
                                          style: const TextStyle(fontSize: 11, color: AppColors.muted),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _FiltroChip extends StatelessWidget {
  const _FiltroChip({required this.label, required this.selecionado, required this.onTap});
  final String label;
  final bool selecionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selecionado,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primarySoft,
      labelStyle: TextStyle(
        color: selecionado ? AppColors.primary : AppColors.muted,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
      backgroundColor: AppColors.surface,
      side: BorderSide(color: selecionado ? AppColors.primary : AppColors.line),
    );
  }
}
