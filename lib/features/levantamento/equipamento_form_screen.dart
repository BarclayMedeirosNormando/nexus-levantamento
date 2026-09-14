import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme.dart';
import '../../data/local/catalogo_repository.dart';
import '../../data/local/equipamentos_repository.dart';
import '../../data/remote/auth_service.dart';
import 'barcode_scanner_screen.dart';
import 'catalogo_picker_sheet.dart';
import 'sugestoes_chips.dart';

/// Tela 6 do spec — formulário de Equipamento (criar/editar), dentro de um
/// Ambiente.
///
/// Captura de foto/código de barras/OCR (2026-09-12): foto (image_picker),
/// leitura de código de barras (mobile_scanner) e OCR de etiqueta
/// (google_mlkit_text_recognition) são plugins mobile-only — sem
/// implementação no Windows/Linux/macOS, então só dá pra testar de verdade
/// num Android (emulador ou aparelho); no build desktop os botões de câmera
/// existem mas não vão funcionar. A foto em si nunca exige internet — só
/// grava um caminho local (ver `EquipamentosRepository`/`database.dart`
/// v3); quem sobe pro Drive de fato é o `FotoUploadService`, rodado a cada
/// sincronização (ver `SyncEngine`).
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
  final _picker = ImagePicker();

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

  String? _fotoEtiquetaPath;
  String? _fotoEquipamentoPath;
  List<String> _linhasOcr = const [];
  bool _reconhecendoTexto = false;

  bool _salvando = false;

  bool get _editando => widget.existente != null;

  @override
  void initState() {
    super.initState();
    // Equipamento novo já começa com "Bom" pré-selecionado (pedido do
    // usuário, 2026-09-12) — a maioria dos equipamentos levantados está em
    // bom estado, então isso poupa um toque repetido; editar um já
    // existente sempre respeita o que já estava salvo (mesmo que vazio).
    _estado = widget.existente?.estado ?? 'Bom';
    _fotoEtiquetaPath = widget.existente?.fotoEtiquetaLocalPath;
    _fotoEquipamentoPath = widget.existente?.fotoEquipamentoLocalPath;
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

  // -- Foto / OCR / código de barras --------------------------------------

  /// 2026-09-14: agora com try/catch — antes, se a permissão de câmera
  /// estivesse negada (ou qualquer outra falha do image_picker), a exceção
  /// não era tratada e o técnico via a tela de erro vermelha do Flutter em
  /// vez de uma mensagem explicando o que fazer. Isso também pode ter sido
  /// a origem do "ícone de exclamação" relatado em campo ao tirar foto da
  /// etiqueta (de onde saem tombamento e número de série via OCR).
  Future<void> _tirarFoto({required bool etiqueta}) async {
    final XFile? arquivo;
    try {
      arquivo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 85,
      );
    } catch (e) {
      if (!mounted) return;
      final negada = e is PlatformException && e.code == 'camera_access_denied';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            negada
                ? 'Permissão de câmera negada. Habilite a Câmera nas configurações do Android para o app Nexus Levantamento.'
                : 'Não foi possível abrir a câmera. Tente de novo.',
          ),
        ),
      );
      return;
    }
    if (arquivo == null || !mounted) return;
    setState(() {
      if (etiqueta) {
        _fotoEtiquetaPath = arquivo!.path;
        _linhasOcr = const [];
      } else {
        _fotoEquipamentoPath = arquivo!.path;
      }
    });
    // OCR só faz sentido na foto da etiqueta (é onde ficam tombamento/série
    // impressos) — a foto do equipamento em si não passa por reconhecimento
    // de texto nenhum.
    if (etiqueta) {
      await _rodarOcr(arquivo.path);
    }
  }

  void _removerFoto({required bool etiqueta}) {
    setState(() {
      if (etiqueta) {
        _fotoEtiquetaPath = null;
        _linhasOcr = const [];
      } else {
        _fotoEquipamentoPath = null;
      }
    });
  }

  /// Roda OCR sobre a foto da etiqueta e junta as linhas de texto
  /// reconhecidas — mostradas depois como chips que o técnico toca pra
  /// preencher Tombamento ou Nº de Série (ver [_usarTextoOcr]), sem tentar
  /// adivinhar sozinho qual linha é qual (etiquetas variam demais de escola
  /// pra escola pra confiar num "auto-preenchimento"). Falha de OCR nunca
  /// bloqueia o formulário — é só uma ajuda a mais; sem ela, o técnico
  /// preenche os campos manualmente do mesmo jeito de sempre.
  Future<void> _rodarOcr(String caminho) async {
    setState(() => _reconhecendoTexto = true);
    try {
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final resultado = await recognizer.processImage(InputImage.fromFilePath(caminho));
      await recognizer.close();

      final linhas = <String>[];
      for (final bloco in resultado.blocks) {
        for (final linha in bloco.lines) {
          final texto = linha.text.trim();
          if (texto.isNotEmpty && !linhas.contains(texto)) linhas.add(texto);
        }
      }
      if (!mounted) return;
      setState(() => _linhasOcr = linhas);
    } catch (_) {
      if (!mounted) return;
      setState(() => _linhasOcr = const []);
    } finally {
      if (mounted) setState(() => _reconhecendoTexto = false);
    }
  }

  void _usarTextoOcr(String texto, {required bool numSerie}) {
    setState(() {
      if (numSerie) {
        _numSerieController.text = texto;
      } else {
        _tombamentoController.text = texto;
      }
    });
  }

  /// 2026-09-14: agora aceita [numSerie] pra reaproveitar a mesma tela de
  /// scanner tanto pro botão do Tombamento quanto pro do Nº de Série (antes
  /// só o Tombamento tinha o botão de ler código de barras — reportado em
  /// campo como o campo de Nº de Série "não é igual ao" de Tombamento).
  Future<void> _abrirScanner({required bool numSerie}) async {
    final codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (codigo == null || !mounted) return;
    setState(() {
      if (numSerie) {
        _numSerieController.text = codigo;
      } else {
        _tombamentoController.text = codigo;
      }
    });
  }

  // -- Duplicidade / salvar -------------------------------------------------

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
      fotoEtiquetaLocalPath: _fotoEtiquetaPath,
      fotoEquipamentoLocalPath: _fotoEquipamentoPath,
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

          _buildFotoTile(
            titulo: 'FOTO DA ETIQUETA',
            caminho: _fotoEtiquetaPath,
            onTirar: () => _tirarFoto(etiqueta: true),
            onRemover: () => _removerFoto(etiqueta: true),
          ),
          if (_reconhecendoTexto)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Lendo texto da etiqueta...', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
          _buildOcrChips(),
          const SizedBox(height: 16),

          const Text('TOMBAMENTO', style: _labelStyle),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _tombamentoController,
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
                child: IconButton(
                  onPressed: () => _abrirScanner(numSerie: false),
                  icon: const Icon(Icons.qr_code_scanner, size: 20, color: AppColors.primary),
                  tooltip: 'Ler código de barras',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          const Text('Nº DE SÉRIE', style: _labelStyle),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _numSerieController,
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
                child: IconButton(
                  onPressed: () => _abrirScanner(numSerie: true),
                  icon: const Icon(Icons.qr_code_scanner, size: 20, color: AppColors.primary),
                  tooltip: 'Ler código de barras',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _buildFotoTile(
            titulo: 'FOTO DO EQUIPAMENTO',
            caminho: _fotoEquipamentoPath,
            onTirar: () => _tirarFoto(etiqueta: false),
            onRemover: () => _removerFoto(etiqueta: false),
          ),
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

  Widget _buildFotoTile({
    required String titulo,
    required String? caminho,
    required VoidCallback onTirar,
    required VoidCallback onRemover,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: _labelStyle),
        const SizedBox(height: 6),
        if (caminho == null)
          OutlinedButton.icon(
            onPressed: onTirar,
            icon: const Icon(Icons.camera_alt_outlined, size: 18),
            label: const Text('Tirar foto'),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                Image.file(
                  File(caminho),
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  // Se o arquivo tiver sumido (ex: cache do sistema
                  // limpo), mostra um placeholder em vez de quebrar a
                  // tela — a pessoa só tira a foto de novo.
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 140,
                    color: AppColors.surface,
                    alignment: Alignment.center,
                    child: const Text(
                      'Foto não encontrada — tire outra',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Row(
                    children: [
                      _miniIconButton(icon: Icons.refresh, tooltip: 'Tirar outra', onPressed: onTirar),
                      const SizedBox(width: 4),
                      _miniIconButton(icon: Icons.close, tooltip: 'Remover', onPressed: onRemover),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _miniIconButton({required IconData icon, required String tooltip, required VoidCallback onPressed}) {
    return Material(
      color: Colors.black.withOpacity(0.55),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: Colors.white),
        tooltip: tooltip,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildOcrChips() {
    if (_linhasOcr.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Texto lido na etiqueta — toque pra usar como Tombamento, ou na setinha pra usar como Nº de Série:',
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _linhasOcr
                .map(
                  (linha) => InputChip(
                    label: Text(linha, style: const TextStyle(fontSize: 12)),
                    onPressed: () => _usarTextoOcr(linha, numSerie: false),
                    deleteIcon: const Icon(Icons.arrow_forward, size: 14),
                    onDeleted: () => _usarTextoOcr(linha, numSerie: true),
                  ),
                )
                .toList(),
          ),
        ],
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
