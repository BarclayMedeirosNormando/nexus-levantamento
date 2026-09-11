import 'package:flutter/material.dart';
import '../../core/location_helper.dart';
import '../../core/theme.dart';
import '../../data/local/auxiliares_repository.dart';
import '../../data/local/escolas_repository.dart';
import '../../data/local/levantamentos_repository.dart';
import '../../data/remote/auth_service.dart';
import '../levantamento/levantamento_screen.dart';
import '../levantamento/selecao_auxiliares_screen.dart';

/// Dados cadastrais da escola + abertura/continuação de levantamento (Tela
/// 3 do spec), incluindo a seleção opcional de técnicos auxiliares antes de
/// abrir um levantamento novo (§2/§5b).
class EscolaDetailScreen extends StatefulWidget {
  const EscolaDetailScreen({super.key, required this.escola, required this.session});
  final Escola escola;
  final Session session;

  @override
  State<EscolaDetailScreen> createState() => _EscolaDetailScreenState();
}

class _EscolaDetailScreenState extends State<EscolaDetailScreen> {
  final _levantamentosRepo = LevantamentosRepository();
  final _auxiliaresRepo = AuxiliaresRepository();

  bool _carregando = true;
  bool _abrindo = false;
  Levantamento? _emAndamento;
  List<Levantamento> _historico = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final emAndamento = await _levantamentosRepo.buscarEmAndamento(
      inep: widget.escola.inep,
      matricula: widget.session.matricula,
      isAdm: widget.session.isAdm,
    );
    final historico = await _levantamentosRepo.listarHistorico(
      inep: widget.escola.inep,
      matricula: widget.session.matricula,
      isAdm: widget.session.isAdm,
    );
    if (!mounted) return;
    setState(() {
      _emAndamento = emAndamento;
      _historico = historico;
      _carregando = false;
    });
  }

  Future<void> _continuarOuAbrir() async {
    if (_emAndamento != null) {
      _irParaLevantamento(_emAndamento!);
      return;
    }

    // Passo opcional antes de abrir: escolher auxiliares (§2/§5 Tela 3 do
    // spec). `null` = a pessoa voltou sem escolher nada -> cancela a
    // abertura; lista vazia = "abrir sem auxiliares", segue normalmente.
    final auxiliares = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => SelecaoAuxiliaresScreen(matriculaAtual: widget.session.matricula),
      ),
    );
    if (auxiliares == null || !mounted) return;

    setState(() => _abrindo = true);
    // Captura de GPS é "best effort" — nunca bloqueia a abertura (ver
    // LocationHelper). DATA_INICIO é sempre o momento real da criação.
    final posicao = await LocationHelper.tentarCapturar();
    final levantamento = await _levantamentosRepo.criar(
      inep: widget.escola.inep,
      matricula: widget.session.matricula,
      lat: posicao?.lat,
      long: posicao?.long,
    );
    if (auxiliares.isNotEmpty) {
      await _auxiliaresRepo.adicionarEmLote(idLevantamento: levantamento.id, matriculas: auxiliares);
    }
    if (!mounted) return;
    setState(() {
      _abrindo = false;
      _emAndamento = levantamento;
      _historico = [levantamento, ..._historico];
    });
    _irParaLevantamento(levantamento);
  }

  void _irParaLevantamento(Levantamento levantamento) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => LevantamentoScreen(escola: widget.escola, levantamento: levantamento, session: widget.session),
          ),
        )
        .then((_) {
      // Ao voltar (ex.: levantamento foi concluído/reaberto em outra tela),
      // recarrega — o histórico visível pra este usuário pode ter mudado
      // (ver regra de visibilidade em LevantamentosRepository).
      if (mounted) _carregar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.escola.nome)),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _InfoRow(label: 'INEP', value: widget.escola.inep),
                _InfoRow(label: 'Município', value: widget.escola.municipio ?? '—'),
                _InfoRow(label: 'Regional', value: widget.escola.regional ?? '—'),
                _InfoRow(label: 'Endereço', value: widget.escola.endereco ?? '—'),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _abrindo ? null : _continuarOuAbrir,
                    icon: _abrindo
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(_emAndamento != null ? Icons.play_arrow_rounded : Icons.add_circle_outline, size: 20),
                    label: Text(
                      _abrindo
                          ? 'Abrindo...'
                          : (_emAndamento != null ? 'Continuar levantamento em andamento' : 'Novo levantamento'),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Histórico',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink),
                ),
                const SizedBox(height: 8),
                if (_historico.isEmpty)
                  Text(
                    widget.session.isAdm
                        ? 'Nenhum levantamento feito nesta escola ainda.'
                        : 'Nenhum levantamento em andamento seu (ou onde você é auxiliar) nesta escola.',
                    style: const TextStyle(color: AppColors.muted, fontSize: 13),
                  )
                else
                  ..._historico.map(
                    (lv) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              lv.status == 'concluido' ? Icons.check_circle_outline : Icons.hourglass_top_rounded,
                              size: 18,
                              color: lv.status == 'concluido' ? AppColors.success : AppColors.warning,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                lv.status == 'concluido' ? 'Concluído' : 'Em andamento',
                                style: const TextStyle(fontSize: 13, color: AppColors.ink, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text(
                              lv.tecnicoAbertura,
                              style: const TextStyle(fontSize: 12, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
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
