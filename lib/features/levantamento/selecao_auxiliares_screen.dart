import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/auxiliares_repository.dart';

/// Passo opcional na abertura de um levantamento (Tela 3 do spec): escolher
/// quais outros técnicos, além de quem está abrindo, vão enxergar e poder
/// editar esse levantamento (LEVANTAMENTO_TECNICOS — ver §2/§5b). Devolve a
/// lista de matrículas selecionadas (pode ser vazia — "abrir sem
/// auxiliares") via `Navigator.pop`; só devolve `null` se a pessoa usar o
/// botão de voltar do sistema, cancelando a abertura do levantamento por
/// inteiro (tratado pelo chamador).
class SelecaoAuxiliaresScreen extends StatefulWidget {
  const SelecaoAuxiliaresScreen({super.key, required this.matriculaAtual});
  final String matriculaAtual;

  @override
  State<SelecaoAuxiliaresScreen> createState() => _SelecaoAuxiliaresScreenState();
}

class _SelecaoAuxiliaresScreenState extends State<SelecaoAuxiliaresScreen> {
  final _repo = AuxiliaresRepository();
  bool _carregando = true;
  List<TecnicoOpcao> _tecnicos = const [];
  final Set<String> _selecionados = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final tecnicos = await _repo.listarTecnicosDisponiveis(excluirMatricula: widget.matriculaAtual);
    if (!mounted) return;
    setState(() {
      _tecnicos = tecnicos;
      _carregando = false;
    });
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
                      'Nenhum outro técnico com login habilitado sincronizado ainda. Pode abrir sozinho e adicionar auxiliar depois.',
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
                        'Opcional. Quem você marcar aqui também vai enxergar e poder editar esse levantamento enquanto ele estiver em andamento — dá pra adicionar (ou remover) gente depois também.',
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
                    onPressed: () => Navigator.of(context).pop(_selecionados.toList()),
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: Text(
                      _selecionados.isEmpty
                          ? 'Abrir sem auxiliares'
                          : 'Abrir com ${_selecionados.length} auxiliar${_selecionados.length == 1 ? '' : 'es'}',
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
