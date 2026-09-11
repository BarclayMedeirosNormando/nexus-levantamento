import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/ambientes_repository.dart';

/// Tela cheia pra completar a lista de ambientes depois da seleção inicial
/// (Tela 4 do spec) — substitui o antigo bottom sheet, que só deixava
/// adicionar um ambiente padrão por vez (tocava e já fechava) e podia
/// estourar a altura da tela com a lista de padrões restante. Aqui dá pra
/// marcar vários itens padrão de uma vez (igual à seleção inicial) e ainda
/// criar um ambiente avulso de nome livre na mesma confirmação.
///
/// Devolve `true` via `Navigator.pop` se algo foi criado (pra quem chamou
/// saber que precisa recarregar a lista), ou `null`/`false` se a pessoa só
/// voltou sem criar nada.
class AdicionarAmbienteScreen extends StatefulWidget {
  const AdicionarAmbienteScreen({
    super.key,
    required this.idLevantamento,
    required this.inep,
    required this.matricula,
    required this.padraoRestantes,
  });
  final String idLevantamento;
  final String inep;
  final String matricula;
  final List<AmbientePadrao> padraoRestantes;

  @override
  State<AdicionarAmbienteScreen> createState() => _AdicionarAmbienteScreenState();
}

class _AdicionarAmbienteScreenState extends State<AdicionarAmbienteScreen> {
  final _repo = AmbientesRepository();
  final Set<String> _selecionados = {};
  final _nomeLivreController = TextEditingController();
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    // Só pra atualizar o contador no botão quando a pessoa digita um nome
    // livre — não precisa recarregar nada do banco.
    _nomeLivreController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nomeLivreController.dispose();
    super.dispose();
  }

  int get _totalASalvar => _selecionados.length + (_nomeLivreController.text.trim().isNotEmpty ? 1 : 0);

  Future<void> _confirmar() async {
    if (_totalASalvar == 0) return;
    setState(() => _salvando = true);

    if (_selecionados.isNotEmpty) {
      final selecionados = widget.padraoRestantes.where((p) => _selecionados.contains(p.idTipoAmbiente)).toList();
      await _repo.criarEmLote(
        idLevantamento: widget.idLevantamento,
        inep: widget.inep,
        matricula: widget.matricula,
        selecionados: selecionados,
      );
    }
    final nomeLivre = _nomeLivreController.text.trim();
    if (nomeLivre.isNotEmpty) {
      await _repo.criarUm(
        idLevantamento: widget.idLevantamento,
        inep: widget.inep,
        matricula: widget.matricula,
        idTipoAmbiente: null,
        nomeAmbiente: nomeLivre,
        origem: 'avulso',
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final semPadraoRestante = widget.padraoRestantes.isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar ambiente')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        children: [
          if (!semPadraoRestante) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Text(
                'Marque quantos precisar — todos são adicionados juntos.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Text(
                'DA LISTA PADRÃO',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: AppColors.muted, letterSpacing: 0.5),
              ),
            ),
            ...widget.padraoRestantes.map(
              (p) => CheckboxListTile(
                value: _selecionados.contains(p.idTipoAmbiente),
                activeColor: AppColors.primary,
                title: Text(p.nomePadrao, style: const TextStyle(fontSize: 14, color: AppColors.ink)),
                onChanged: (marcado) {
                  setState(() {
                    if (marcado == true) {
                      _selecionados.add(p.idTipoAmbiente);
                    } else {
                      _selecionados.remove(p.idTipoAmbiente);
                    }
                  });
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: AppColors.line),
            ),
          ],
          Padding(
            padding: EdgeInsets.fromLTRB(8, semPadraoRestante ? 0 : 8, 8, 8),
            child: const Text(
              'NOME LIVRE (opcional)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: AppColors.muted, letterSpacing: 0.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextField(
              controller: _nomeLivreController,
              decoration: const InputDecoration(hintText: 'Ex.: Depósito, Pátio coberto...'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_salvando || _totalASalvar == 0) ? null : _confirmar,
              icon: _salvando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline, size: 20),
              label: Text(
                _salvando
                    ? 'Adicionando...'
                    : (_totalASalvar == 0 ? 'Selecione ao menos um' : 'Adicionar ($_totalASalvar)'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
