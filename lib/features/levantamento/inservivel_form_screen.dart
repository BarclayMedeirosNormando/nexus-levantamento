import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/catalogo_repository.dart';
import '../../data/local/equipamentos_repository.dart';
import 'sugestoes_chips.dart';

/// Formulário de equipamento inservível (parte da Tela 5 do spec) — mesma
/// tela pra criar e editar. Diferente do Equipamento "normal": não tem
/// Tombamento/Nº de Série (sucata, sem identificação individual relevante)
/// e tem uma QUANTIDADE, pra não precisar criar um registro por unidade
/// quando é um lote (ex.: "8 monitores CRT quebrados").
class InservivelFormScreen extends StatefulWidget {
  const InservivelFormScreen({
    super.key,
    required this.idAmbiente,
    required this.idLevantamento,
    required this.inep,
    required this.matricula,
    this.existente,
  });

  final String idAmbiente;
  final String idLevantamento;
  final String inep;
  final String matricula;
  final EquipamentoInservivel? existente;

  @override
  State<InservivelFormScreen> createState() => _InservivelFormScreenState();
}

class _InservivelFormScreenState extends State<InservivelFormScreen> {
  final _repo = EquipamentosRepository();

  late final _tipoController = TextEditingController(text: widget.existente?.tipoEquipamento ?? '');
  late final _marcaController = TextEditingController(text: widget.existente?.marca ?? '');
  late final _modeloController = TextEditingController(text: widget.existente?.modelo ?? '');
  late final _quantidadeController =
      TextEditingController(text: (widget.existente?.quantidade ?? 1).toString());

  bool _salvando = false;

  bool get _editando => widget.existente != null;

  @override
  void dispose() {
    _tipoController.dispose();
    _marcaController.dispose();
    _modeloController.dispose();
    _quantidadeController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final tipo = _tipoController.text.trim();
    if (tipo.isEmpty) {
      AppSnackbar.aviso(context, 'Informe o tipo do equipamento.');
      return;
    }
    final quantidade = int.tryParse(_quantidadeController.text.trim()) ?? 1;

    setState(() => _salvando = true);
    await _repo.salvarInservivel(
      id: widget.existente?.id,
      idAmbiente: widget.idAmbiente,
      idLevantamento: widget.idLevantamento,
      inep: widget.inep,
      tipoEquipamento: tipo,
      marca: _marcaController.text.trim().isEmpty ? null : _marcaController.text.trim(),
      modelo: _modeloController.text.trim().isEmpty ? null : _modeloController.text.trim(),
      quantidade: quantidade < 1 ? 1 : quantidade,
      matricula: widget.matricula,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar inservível' : 'Novo inservível')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: [
          const Text('TIPO DE EQUIPAMENTO', style: _labelStyle),
          const SizedBox(height: 6),
          TextField(controller: _tipoController, textCapitalization: TextCapitalization.words),
          const SizedBox(height: 6),
          SugestoesChips(
            opcoes: CatalogoRepository.tiposSugeridos,
            controller: _tipoController,
            onSelecionado: () => setState(() {}),
          ),
          const SizedBox(height: 16),

          const Text('MARCA', style: _labelStyle),
          const SizedBox(height: 6),
          TextField(controller: _marcaController, textCapitalization: TextCapitalization.words),
          const SizedBox(height: 6),
          SugestoesChips(
            opcoes: CatalogoRepository.marcasSugeridas,
            controller: _marcaController,
            onSelecionado: () => setState(() {}),
          ),
          const SizedBox(height: 16),

          const Text('MODELO', style: _labelStyle),
          const SizedBox(height: 6),
          TextField(controller: _modeloController, textCapitalization: TextCapitalization.words),
          const SizedBox(height: 16),

          const Text('QUANTIDADE', style: _labelStyle),
          const SizedBox(height: 6),
          TextField(controller: _quantidadeController, keyboardType: TextInputType.number),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _salvando ? null : _salvar,
              icon: _salvando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline, size: 20),
              label: Text(_salvando ? 'Salvando...' : 'Salvar'),
            ),
          ),
        ),
      ),
    );
  }
}

const _labelStyle = TextStyle(
  color: AppColors.muted,
  fontSize: 11,
  fontWeight: FontWeight.w800,
  letterSpacing: 0.5,
);
