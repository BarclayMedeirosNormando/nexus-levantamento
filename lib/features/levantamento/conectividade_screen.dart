import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/ambientes_repository.dart';
import '../../data/local/conectividade_repository.dart';
import '../../data/local/escolas_repository.dart';
import '../../data/local/levantamentos_repository.dart';
import 'conectividade_form_escola_screen.dart';

/// Tela 7 do spec — lista de links de internet da escola dentro deste
/// levantamento (pode ter mais de um: vários contratos do Estado e/ou
/// links pagos pela própria escola — "escola conectada"). Cada card já
/// mostra o essencial e abre pra edição (medição/status) ao tocar.
class ConectividadeScreen extends StatefulWidget {
  const ConectividadeScreen({
    super.key,
    required this.escola,
    required this.levantamento,
    required this.ambientes,
    required this.matricula,
  });
  final Escola escola;
  final Levantamento levantamento;
  final List<Ambiente> ambientes;
  final String matricula;

  @override
  State<ConectividadeScreen> createState() => _ConectividadeScreenState();
}

class _ConectividadeScreenState extends State<ConectividadeScreen> {
  final _repo = ConectividadeRepository();
  bool _carregando = true;
  bool _criando = false;
  List<Conectividade> _links = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final links = await _repo.listarPorLevantamento(widget.levantamento.id);
    if (!mounted) return;
    setState(() {
      _links = links;
      _carregando = false;
    });
  }

  String _nomeAmbiente(String? id) {
    if (id == null) return '—';
    final match = widget.ambientes.where((a) => a.id == id);
    return match.isEmpty ? '—' : match.first.nomeAmbiente;
  }

  Future<void> _criarDeEstado() async {
    setState(() => _criando = true);
    final criados = await _repo.criarLinksDeEstado(
      idLevantamento: widget.levantamento.id,
      inep: widget.escola.inep,
      matricula: widget.matricula,
    );
    if (!mounted) return;
    setState(() => _criando = false);
    await _carregar();
    if (!mounted) return;
    final mensagem = criados == 0
        ? 'Nenhum contrato do Estado novo pra adicionar (ou a escola não tem contrato cadastrado).'
        : '$criados link${criados == 1 ? '' : 's'} do Estado adicionado${criados == 1 ? '' : 's'}.';
    AppSnackbar.info(context, mensagem);
  }

  Future<void> _abrirFormEscola({Conectividade? existente}) async {
    final salvou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ConectividadeFormEscolaScreen(
          idLevantamento: widget.levantamento.id,
          inep: widget.escola.inep,
          matricula: widget.matricula,
          ambientes: widget.ambientes,
          existente: existente,
        ),
      ),
    );
    if (salvou == true) {
      await _carregar();
    }
  }

  Future<void> _abrirOpcoesCriar() async {
    final opcao = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Criar conectividade',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_outlined, color: AppColors.primary),
              title: const Text('Internet do Estado'),
              subtitle: const Text(
                'Cria um link pra cada contrato já cadastrado dessa escola',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              onTap: () => Navigator.of(sheetContext).pop('estado'),
            ),
            ListTile(
              leading: const Icon(Icons.school_outlined, color: AppColors.primary),
              title: const Text('Internet paga pela escola'),
              subtitle: const Text(
                'Escola conectada — sem contrato do Estado',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              onTap: () => Navigator.of(sheetContext).pop('escola'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (opcao == 'estado') {
      await _criarDeEstado();
    } else if (opcao == 'escola') {
      await _abrirFormEscola();
    }
  }

  static const _statusValidos = {'ATIVA', 'INATIVA', 'NAO_ENCONTRADA'};

  Future<void> _editarEstado(Conectividade link) async {
    final downloadController = TextEditingController(text: link.velocidadeMedidaDownloadMbps?.toString() ?? '');
    final uploadController = TextEditingController(text: link.velocidadeMedidaUploadMbps?.toString() ?? '');
    // Só aceita um valor que exista de verdade nos itens do dropdown abaixo
    // — sem isso, um link sincronizado de outro aparelho com STATUS_LINK
    // vazio ("", não null — é assim que uma célula em branco do Sheets
    // chega aqui, ver `_conectividadeParaLocal` no motor de sync) quebrava
    // o DropdownButtonFormField com "Either zero or 2 or more
    // DropdownMenuItems were detected with the same value". Mesmo padrão já
    // usado no dropdown de Ambiente em ConectividadeFormEscolaScreen.
    String? status = _statusValidos.contains(link.statusLink) ? link.statusLink : null;

    final salvou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(link.operadora?.isNotEmpty == true ? link.operadora! : 'Link do Estado'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (link.velocidadeContratadaMbps != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Contratada: ${link.velocidadeContratadaMbps} Mbps',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ),
                TextField(
                  controller: downloadController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Velocidade medida — download (Mbps)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: uploadController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Velocidade medida — upload (Mbps)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(labelText: 'Status do link'),
                  items: const [
                    DropdownMenuItem(value: 'ATIVA', child: Text('Ativa')),
                    DropdownMenuItem(value: 'INATIVA', child: Text('Inativa')),
                    DropdownMenuItem(value: 'NAO_ENCONTRADA', child: Text('Não encontrada')),
                  ],
                  onChanged: (v) => setDialogState(() => status = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (salvou != true) return;
    await _repo.atualizarMedicaoEstado(
      id: link.id,
      velocidadeDownload: double.tryParse(downloadController.text.trim().replaceAll(',', '.')),
      velocidadeUpload: double.tryParse(uploadController.text.trim().replaceAll(',', '.')),
      statusLink: status,
    );
    await _carregar();
  }

  Future<void> _remover(Conectividade link) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover link?'),
        content: const Text('Essa ação não pode ser desfeita.'),
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
    await _repo.remover(link.id);
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conectividade')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _links.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Nenhum link cadastrado ainda. Toque em "Criar Conectividade" pra começar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  itemCount: _links.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final link = _links[index];
                    return _ConectividadeCard(
                      link: link,
                      nomeAmbiente: _nomeAmbiente(link.idAmbiente),
                      onTap: () => link.isEstado ? _editarEstado(link) : _abrirFormEscola(existente: link),
                      onRemover: () => _remover(link),
                    );
                  },
                ),
      floatingActionButton: _criando
          ? FloatingActionButton.extended(
              onPressed: null,
              icon: const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              label: const Text('Criando...'),
            )
          : FloatingActionButton.extended(
              onPressed: _abrirOpcoesCriar,
              icon: const Icon(Icons.add),
              label: const Text('Criar Conectividade'),
            ),
    );
  }
}

class _ConectividadeCard extends StatelessWidget {
  const _ConectividadeCard({
    required this.link,
    required this.nomeAmbiente,
    required this.onTap,
    required this.onRemover,
  });
  final Conectividade link;
  final String nomeAmbiente;
  final VoidCallback onTap;
  final VoidCallback onRemover;

  Color _statusColor() {
    switch (link.statusLink) {
      case 'ATIVA':
        return AppColors.success;
      case 'INATIVA':
      case 'NAO_ENCONTRADA':
        return AppColors.warning;
      default:
        return AppColors.muted;
    }
  }

  String _statusLabel() {
    switch (link.statusLink) {
      case 'ATIVA':
        return 'Ativa';
      case 'INATIVA':
        return 'Inativa';
      case 'NAO_ENCONTRADA':
        return 'Não encontrada';
      default:
        return 'Sem medição ainda';
    }
  }

  @override
  Widget build(BuildContext context) {
    final medida = (link.velocidadeMedidaDownloadMbps != null || link.velocidadeMedidaUploadMbps != null)
        ? '${link.velocidadeMedidaDownloadMbps?.toStringAsFixed(0) ?? '—'}↓ / ${link.velocidadeMedidaUploadMbps?.toStringAsFixed(0) ?? '—'}↑ Mbps'
        : 'Sem medição ainda';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
              child: Icon(
                link.isEstado ? Icons.account_balance_outlined : Icons.school_outlined,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    link.operadora?.isNotEmpty == true
                        ? link.operadora!
                        : (link.isEstado ? 'Link do Estado' : 'Link da escola'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(medida, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  if (!link.isEstado)
                    Text('Ambiente: $nomeAmbiente', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                  if (link.isEstado) ...[
                    const SizedBox(height: 2),
                    Text(
                      _statusLabel(),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor()),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
              tooltip: 'Remover',
              onPressed: onRemover,
            ),
          ],
        ),
      ),
    );
  }
}
