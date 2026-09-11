import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/catalogo_repository.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/auth_service.dart';
import '../levantamento/sugestoes_chips.dart';

/// Formulário de criação/edição de modelo no catálogo — tela cheia (não
/// diálogo/bottom sheet), mesmo padrão já usado em outras telas do app
/// (`EquipamentoFormScreen`, `AdicionarAmbienteScreen`, ...). Era um
/// `AlertDialog` (`CriarModeloDialog`) até 2026-09-11: trocado pra tela
/// cheia depois de um crash reproduzível no Windows (`Cannot hit test a
/// render box with no size` / assert do `mouse_tracker.dart`, sessão
/// derrubada) ao abrir o diálogo — o mesmo `SugestoesChips` (ListView
/// horizontal de `ChoiceChip`, que já funciona sem problema dentro de
/// telas cheias como `EquipamentoFormScreen`) parece não conviver bem com
/// o rastreio de mouse do Windows dentro de um `AlertDialog`/`showDialog`.
/// Tela cheia evita esse caminho por completo.
///
/// Reusada em três lugares: botão "Novo modelo" da tela Catálogo de
/// Modelos, botão "Criar modelo" do picker de catálogo (dentro do
/// formulário de Equipamento), e agora também pra EDITAR um modelo já
/// existente (tocar num item da lista do Catálogo de Modelos) — passar
/// [existente] muda o modo pra edição, chamando
/// `CatalogoRepository.atualizarModelo` em vez de `criarModelo`.
class ModeloFormScreen extends StatefulWidget {
  const ModeloFormScreen({
    super.key,
    required this.session,
    this.existente,
    this.tipoInicial,
  });

  final Session session;
  final CatalogoItem? existente;
  final String? tipoInicial;

  @override
  State<ModeloFormScreen> createState() => _ModeloFormScreenState();
}

class _ModeloFormScreenState extends State<ModeloFormScreen> {
  final _repo = CatalogoRepository();
  late final _tipoController =
      TextEditingController(text: widget.existente?.tipoEquipamento ?? widget.tipoInicial ?? '');
  late final _marcaController = TextEditingController(text: widget.existente?.marca ?? '');
  late final _modeloController = TextEditingController(text: widget.existente?.modelo ?? '');
  bool _salvando = false;
  String? _erro;

  bool get _editando => widget.existente != null;

  @override
  void dispose() {
    _tipoController.dispose();
    _marcaController.dispose();
    _modeloController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final tipo = _tipoController.text.trim();
    final marca = _marcaController.text.trim();
    final modelo = _modeloController.text.trim();
    if (tipo.isEmpty || marca.isEmpty || modelo.isEmpty) {
      setState(() => _erro = 'Preencha Tipo, Marca e Modelo.');
      return;
    }

    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final ModeloFormResultado resultado;
      if (_editando) {
        final atualizado = await _repo.atualizarModelo(
          session: widget.session,
          idCatalogo: widget.existente!.idCatalogo,
          tipoEquipamento: tipo,
          marca: marca,
          modelo: modelo,
        );
        resultado = ModeloFormResultado(
          atualizado.item,
          equipamentosAtualizados: atualizado.equipamentosAtualizados,
        );
      } else {
        final criado = await _repo.criarModelo(
          session: widget.session,
          tipoEquipamento: tipo,
          marca: marca,
          modelo: modelo,
        );
        resultado = ModeloFormResultado(criado);
      }
      if (!mounted) return;
      Navigator.of(context).pop(resultado);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erro = _editando
            ? 'Precisa de internet pra salvar as alterações (${e.message}).'
            : 'Precisa de internet pra criar um modelo novo no catálogo (${e.message}). '
                'Se preferir, cancele e digite Tipo/Marca/Modelo direto no formulário — isso continua funcionando offline.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar modelo' : 'Criar modelo no catálogo')),
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

          if (_erro != null) ...[
            const SizedBox(height: 16),
            Text(_erro!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
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

/// Resultado devolvido ao fechar [ModeloFormScreen] (criar ou editar):
/// sempre o [item] resultante; [equipamentosAtualizados] só vem preenchido
/// (!= null) quando foi uma EDIÇÃO — número de equipamentos já cadastrados
/// que tiveram Tipo/Marca/Modelo propagados junto (ver
/// CatalogoRepository.atualizarModelo). Ao criar um modelo novo não existe
/// equipamento nenhum apontando pra esse ID_CATALOGO ainda, então fica
/// null (não faz sentido mostrar "0 atualizados").
class ModeloFormResultado {
  const ModeloFormResultado(this.item, {this.equipamentosAtualizados});
  final CatalogoItem item;
  final int? equipamentosAtualizados;
}
