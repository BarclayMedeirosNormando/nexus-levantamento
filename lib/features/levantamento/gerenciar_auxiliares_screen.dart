import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/auxiliares_repository.dart';

/// Tela cheia pra gerenciar os técnicos auxiliares de um levantamento já
/// aberto (§2/§5b do spec) — substitui o antigo bottom sheet, que só deixava
/// adicionar OU remover um técnico por vez (tocava e já confirmava na hora,
/// fechando o sheet). Aqui dá pra marcar/desmarcar vários de uma vez (igual
/// ao padrão já usado em AdicionarAmbienteScreen/SelecaoAuxiliaresScreen) e
/// só grava tudo (adições + remoções) numa única confirmação.
///
/// Devolve `true` via `Navigator.pop` se algo foi alterado (pra quem chamou
/// saber que precisa recarregar a lista de auxiliares), ou `null`/`false` se
/// a pessoa só voltou sem confirmar nada.
class GerenciarAuxiliaresScreen extends StatefulWidget {
  const GerenciarAuxiliaresScreen({
    super.key,
    required this.idLevantamento,
    required this.matriculaDono,
  });
  final String idLevantamento;
  final String matriculaDono;

  @override
  State<GerenciarAuxiliaresScreen> createState() => _GerenciarAuxiliaresScreenState();
}

class _GerenciarAuxiliaresScreenState extends State<GerenciarAuxiliaresScreen> {
  final _repo = AuxiliaresRepository();
  bool _carregando = true;
  bool _salvando = false;
  List<TecnicoOpcao> _tecnicos = const [];
  Set<String> _originais = {};
  final Set<String> _selecionados = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final auxiliares = await _repo.listarAuxiliares(widget.idLevantamento);
    final disponiveis = await _repo.listarTecnicosDisponiveis(excluirMatricula: widget.matriculaDono);
    if (!mounted) return;
    final originais = auxiliares.map((t) => t.matricula).toSet();
    // Junta quem já é auxiliar (mesmo que por algum motivo não apareça mais
    // em "disponíveis") com quem está disponível pra adicionar — todo mundo
    // aparece numa lista só, com checkbox.
    final porMatricula = <String, TecnicoOpcao>{
      for (final t in disponiveis) t.matricula: t,
      for (final t in auxiliares) t.matricula: t,
    };
    final tecnicos = porMatricula.values.toList()..sort((a, b) => a.nome.compareTo(b.nome));
    setState(() {
      _tecnicos = tecnicos;
      _originais = originais;
      _selecionados
        ..clear()
        ..addAll(originais);
      _carregando = false;
    });
  }

  bool get _houveMudanca {
    if (_selecionados.length != _originais.length) return true;
    return !_selecionados.containsAll(_originais);
  }

  Future<void> _confirmar() async {
    if (!_houveMudanca) return;
    setState(() => _salvando = true);
    final aAdicionar = _selecionados.difference(_originais).toList();
    final aRemover = _originais.difference(_selecionados).toList();
    if (aAdicionar.isNotEmpty) {
      await _repo.adicionarEmLote(idLevantamento: widget.idLevantamento, matriculas: aAdicionar);
    }
    if (aRemover.isNotEmpty) {
      await _repo.removerEmLote(idLevantamento: widget.idLevantamento, matriculas: aRemover);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Técnicos auxiliares')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _tecnicos.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Nenhum outro técnico com login habilitado sincronizado ainda.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Text(
                        'Marque quem deve enxergar e poder editar esse levantamento. Desmarque pra remover. '
                        'Marque quantos precisar — tudo é salvo junto ao confirmar.',
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ),
                    ..._tecnicos.map(
                      (t) => CheckboxListTile(
                        value: _selecionados.contains(t.matricula),
                        activeColor: AppColors.primary,
                        title: Text(t.nome, style: const TextStyle(fontSize: 14, color: AppColors.ink)),
                        subtitle: Text(
                          'Matrícula ${t.matricula}',
                          style: const TextStyle(fontSize: 11, color: AppColors.muted),
                        ),
                        onChanged: (marcado) {
                          setState(() {
                            if (marcado == true) {
                              _selecionados.add(t.matricula);
                            } else {
                              _selecionados.remove(t.matricula);
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _carregando
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_salvando || !_houveMudanca) ? null : _confirmar,
                    icon: _salvando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_outline, size: 20),
                    label: Text(
                      _salvando
                          ? 'Salvando...'
                          : (_houveMudanca
                              ? 'Salvar (${_selecionados.length} auxiliar${_selecionados.length == 1 ? '' : 'es'})'
                              : 'Nenhuma alteração'),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
