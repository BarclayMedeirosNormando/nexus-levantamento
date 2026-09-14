import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../data/local/escolas_repository.dart';
import '../../data/local/fotos_levantamento_repository.dart';
import '../../data/local/levantamentos_repository.dart';

/// Galeria geral do levantamento (2026-09-14) — fotos no nível da escola
/// (Fachada, Laboratório, Roteador, Equipamento, Documento, Outro), não
/// amarradas a um equipamento específico (isso já existe em
/// `equipamento_form_screen.dart`, via FOTO_ETIQUETA_URL/FOTO_EQUIPAMENTO_URL).
/// Replica a aba FOTOS que já existia na planilha "Nexus Inventario" do
/// AppSheet — ver `FotosLevantamentoRepository` pra mais contexto e pro
/// motor de sync (push/pull já cobertos em `LevantamentoSyncService`, upload
/// em `FotoUploadService`).
///
/// Mesma filosofia offline-first do resto do app: tirar a foto nunca exige
/// internet — só grava o caminho local; quem sobe pro Drive é o
/// FotoUploadService, no próximo sync (manual ou automático).
class FotosLevantamentoScreen extends StatefulWidget {
  const FotosLevantamentoScreen({
    super.key,
    required this.escola,
    required this.levantamento,
    required this.matricula,
  });
  final Escola escola;
  final Levantamento levantamento;
  final String matricula;

  @override
  State<FotosLevantamentoScreen> createState() => _FotosLevantamentoScreenState();
}

class _FotosLevantamentoScreenState extends State<FotosLevantamentoScreen> {
  final _repo = FotosLevantamentoRepository();
  final _picker = ImagePicker();

  bool _carregando = true;
  List<FotoLevantamento> _fotos = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final fotos = await _repo.listarPorLevantamento(widget.levantamento.id);
    if (!mounted) return;
    setState(() {
      _fotos = fotos;
      _carregando = false;
    });
  }

  Future<void> _adicionarFoto() async {
    final escolha = await _abrirEscolhaTipo();
    if (escolha == null || !mounted) return;

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
      AppSnackbar.erro(
        context,
        negada
            ? 'Permissão de câmera negada. Habilite a Câmera nas configurações do Android para o app Nexus Levantamento.'
            : 'Não foi possível abrir a câmera. Tente de novo.',
      );
      return;
    }
    if (arquivo == null || !mounted) return;

    await _repo.adicionar(
      idLevantamento: widget.levantamento.id,
      inep: widget.escola.inep,
      matricula: widget.matricula,
      tipoFoto: escolha.tipo,
      outroTipoFoto: escolha.outroTipo,
      descricao: escolha.descricao,
      fotoLocalPath: arquivo.path,
    );
    await _carregar();
  }

  Future<_EscolhaTipoFoto?> _abrirEscolhaTipo() async {
    var tipoSelecionado = FotosLevantamentoRepository.tipos.first;
    final outroController = TextEditingController();
    final descricaoController = TextEditingController();

    final resultado = await showDialog<_EscolhaTipoFoto>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Nova foto'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tipo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: FotosLevantamentoRepository.tipos.map((tipo) {
                    return ChoiceChip(
                      label: Text(tipo),
                      selected: tipoSelecionado == tipo,
                      onSelected: (_) => setDialogState(() => tipoSelecionado = tipo),
                    );
                  }).toList(),
                ),
                if (tipoSelecionado == 'Outro') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: outroController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Qual? (ex: pátio, muro, portão)'),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: descricaoController,
                  decoration: const InputDecoration(labelText: 'Descrição (opcional)'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(
                _EscolhaTipoFoto(
                  tipo: tipoSelecionado,
                  outroTipo: outroController.text.trim().isEmpty ? null : outroController.text.trim(),
                  descricao: descricaoController.text.trim().isEmpty ? null : descricaoController.text.trim(),
                ),
              ),
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Tirar foto'),
            ),
          ],
        ),
      ),
    );
    return resultado;
  }

  Future<void> _remover(FotoLevantamento foto) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover foto?'),
        content: Text('"${foto.rotulo}" — essa ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;
    await _repo.remover(foto.id, matricula: widget.matricula);
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fotos do levantamento')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _fotos.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Nenhuma foto ainda. Toque em "Adicionar foto" para registrar a fachada, o laboratório, o roteador, ou qualquer outra coisa da escola.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: FadeIn(
                    child: GridView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: _fotos.length,
                      itemBuilder: (context, index) {
                        final foto = _fotos[index];
                        return _FotoCard(foto: foto, onRemover: () => _remover(foto));
                      },
                    ),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adicionarFoto,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Adicionar foto'),
      ),
    );
  }
}

class _EscolhaTipoFoto {
  final String tipo;
  final String? outroTipo;
  final String? descricao;
  const _EscolhaTipoFoto({required this.tipo, this.outroTipo, this.descricao});
}

class _FotoCard extends StatelessWidget {
  const _FotoCard({required this.foto, required this.onRemover});
  final FotoLevantamento foto;
  final VoidCallback onRemover;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _FotoThumb(foto: foto),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Material(
                    color: Colors.black.withOpacity(0.55),
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: onRemover,
                      icon: const Icon(Icons.close, size: 16, color: Colors.white),
                      tooltip: 'Remover',
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (foto.fotoUrl == null || foto.fotoUrl!.isEmpty)
                  Positioned(
                    bottom: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Aguardando sync',
                        style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Text(
              foto.rotulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tenta o arquivo local primeiro (foto tirada neste aparelho, ainda não
/// enviada ou já enviada mas com o arquivo ainda presente); se não tiver
/// caminho local (foto de outro técnico, já sincronizada) cai pra URL
/// remota; sem os dois, mostra um placeholder — nunca quebra a tela.
class _FotoThumb extends StatelessWidget {
  const _FotoThumb({required this.foto});
  final FotoLevantamento foto;

  @override
  Widget build(BuildContext context) {
    final caminhoLocal = foto.fotoLocalPath;
    if (caminhoLocal != null && caminhoLocal.isNotEmpty) {
      return Image.file(
        File(caminhoLocal),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholderOuRede(),
      );
    }
    return _placeholderOuRede();
  }

  Widget _placeholderOuRede() {
    final url = foto.fotoUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.primarySoft,
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_outlined, color: AppColors.muted),
    );
  }
}
