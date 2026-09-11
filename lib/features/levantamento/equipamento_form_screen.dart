import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/catalogo_repository.dart';
import '../../data/local/equipamentos_repository.dart';
import '../../data/remote/auth_service.dart';
import 'catalogo_picker_sheet.dart';
import 'sugestoes_chips.dart';

/// Tela 6 do spec — formulário de Equipamento (criar/editar), dentro de um
/// Ambiente. Captura só texto neste incremento: leitura de código de barras
/// (mobile_scanner), OCR de etiqueta (google_mlkit_text_recognition) e foto
/// (image_picker) ficam de fora de propósito — são plugins mobile-only (não
/// dá pra testar no build desktop atual) e ainda não existe pipeline de
/// upload de foto no motor de sync (mandar caminho de arquivo local pro
/// campo FOTO_*_URL corromperia o dado no servidor). Ver spec §9.
///
/// [catalogoInicial] pré-preenche Tipo/Marca/Modelo quando a tela é aberta
/// já com um item escolhido no catálogo (fluxo "catálogo primeiro" a partir
/// de AmbienteDetailScreen) — só se aplica pra equipamento novo
/// ([existente] nulo); editar um já existente sempre parte dos dados dele.
class EquipamentoFormScreen extends StatefulWidget {
  const EquipamentoFormScreen({
    super.key,
    required this.idAmbiente,
    required this.idLevantamento,
    required this.inep,
    required this.session,
    this.existente,
    this.catalogoInicial,
  });

  final String idAmbiente;
  final String idLevantamento;
  final String inep;
  final Session session;
  final Equipamento? existente;
  final CatalogoItem? catalogoInicial;

  @override
  State<EquipamentoFormScreen> createState() => _EquipamentoFormScreenState();
}

class _EquipamentoFormScreenState extends State<EquipamentoFormScreen> {
  final _repo = EquipamentosRepository();

  late final _tipoController = TextEditingController(
    text: widget.existente?.tipoEquipamento ?? widget.catalogoInicial?.tipoEquipamento ?? '',
  );
  late final _marcaController = TextEditingController(
    text: widget.existente?.marca ?? widget.catalogoInicial?.marca ?? '',
  );
  late final _modeloController = TextEditingController(
    text: widget.existente?.modeloExibido ?? widget.catalogoInicial?.modelo ?? '',
  );
  late final _tombamentoController = TextEditingController(text: widget.existente?.tombamento ?? '');
  late final _numSerieController = TextEditingController(text: widget.existente?.numSerie ?? '');
  String? _estado = '';

  bool _salvando = false;

  bool get _editando => widget.existente != null;

  @override
  void initState() {
    super.initState();
    _estado = widget.existente?.estado;
  }

  @override
  void dispose() {
    _tipoController.dispose();
    _marcaController.dispose();
    _modeloController.dispose();
    _tombamentoController.dispose();
    _numSerieController.dispose();
    super.dispose();
  }

  Future<void> _abrirBuscaCatalogo() async {
    final resultado = await showCatalogoPickerSheet(context: context, session: widget.session);
    if (resultado?.item == null || !mounted) return;
    final item = resultado!.item!;
    setState(() {
      _tipoController.text = item.tipoEquipamento;
      _marcaController.text = item.marca ?? '';
      _modeloController.text = item.modelo ?? '';
    });
  }

  Future<bool> _confirmarSeDuplicado() async {
    final achados = await _repo.verificarDuplicidade(
      tombamento: _tombamentoController.text,
      numSerie: _numSerieController.text,
      ignorarId: widget.existente?.id,
    );
    if (achados.isEmpty) return true;
    final descricao = achados
        .map((a) => a.tipo == 'TOMBAMENTO' ? 'Tombamento "${a.valor}"' : 'Nº de Série "${a.valor}"')
        .join(' e ');
    if (!mounted) return true;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Possível duplicidade'),
        content: Text(
          '$descricao já existe em outro equipamento cadastrado neste aparelho. '
          'Pode ser um cadastro repetido por engano — confira antes de continuar.\n\n'
          'Isso é só um aviso local: a checagem que vale de verdade é feita quando sincronizar.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Revisar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Salvar mesmo assim'),
          ),
        ],
      ),
    );
    return confirmar == true;
  }

  Future<void> _salvar() async {
    final tipo = _tipoController.text.trim();
    if (tipo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o tipo do equipamento.')),
      );
      return;
    }

    final podeSalvar = await _confirmarSeDuplicado();
    if (!podeSalvar || !mounted) return;

    setState(() => _salvando = true);
    await _repo.salvar(
      id: widget.existente?.id,
      idAmbiente: widget.idAmbiente,
      idLevantamento: widget.idLevantamento,
      inep: widget.inep,
      tipoEquipamento: tipo,
      marca: _marcaController.text.trim().isEmpty ? null : _marcaController.text.trim(),
      modelo: _modeloController.text.trim().isEmpty ? null : _modeloController.text.trim(),
      tombamento: _tombamentoController.text.trim().isEmpty ? null : _tombamentoController.text.trim(),
      numSerie: _numSerieController.text.trim().isEmpty ? null : _numSerieController.text.trim(),
      estado: _estado,
      matricula: widget.session.matricula,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar equipamento' : 'Novo equipamento'),
        actions: [
          IconButton(
            onPressed: _abrirBuscaCatalogo,
            icon: const Icon(Icons.search),
            tooltip: 'Buscar no catálogo',
          ),
        ],
      ),
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

          const Text('TOMBAMENTO', style: _labelStyle),
          const SizedBox(height: 6),
          TextField(controller: _tombamentoController, textCapitalization: TextCapitalization.characters),
          const SizedBox(height: 16),

          const Text('Nº DE SÉRIE', style: _labelStyle),
          const SizedBox(height: 6),
          TextField(controller: _numSerieController, textCapitalization: TextCapitalization.characters),
          const SizedBox(height: 16),

          const Text('ESTADO DE CONSERVAÇÃO', style: _labelStyle),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: (_estado != null && _estado!.isNotEmpty) ? _estado : null,
            hint: const Text('Selecione'),
            items: CatalogoRepository.estadosEquipamento
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _estado = v),
          ),
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
