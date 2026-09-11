import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/ambientes_repository.dart';
import '../../data/local/conectividade_repository.dart';

/// Formulário de link "Escola" (Tela 7 do spec) — internet paga com recurso
/// próprio da escola, sem contrato do Estado ("escola conectada"). Serve
/// tanto pra criar (`existente == null`) quanto pra editar um já criado.
///
/// Devolve `true` via `Navigator.pop` se salvou algo, ou `null`/`false` se a
/// pessoa só voltou sem salvar.
class ConectividadeFormEscolaScreen extends StatefulWidget {
  const ConectividadeFormEscolaScreen({
    super.key,
    required this.idLevantamento,
    required this.inep,
    required this.matricula,
    required this.ambientes,
    this.existente,
  });
  final String idLevantamento;
  final String inep;
  final String matricula;
  final List<Ambiente> ambientes;
  final Conectividade? existente;

  @override
  State<ConectividadeFormEscolaScreen> createState() => _ConectividadeFormEscolaScreenState();
}

class _ConectividadeFormEscolaScreenState extends State<ConectividadeFormEscolaScreen> {
  final _repo = ConectividadeRepository();
  late final _operadoraController = TextEditingController(text: widget.existente?.operadora ?? '');
  late final _velocidadeContratadaController =
      TextEditingController(text: widget.existente?.velocidadeContratadaMbps ?? '');
  late final _downloadController =
      TextEditingController(text: widget.existente?.velocidadeMedidaDownloadMbps?.toString() ?? '');
  late final _uploadController =
      TextEditingController(text: widget.existente?.velocidadeMedidaUploadMbps?.toString() ?? '');
  String? _idAmbiente;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _idAmbiente = widget.existente?.idAmbiente;
  }

  @override
  void dispose() {
    _operadoraController.dispose();
    _velocidadeContratadaController.dispose();
    _downloadController.dispose();
    _uploadController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    final operadora = _operadoraController.text.trim();
    final velocidadeContratada = _velocidadeContratadaController.text.trim();
    final download = double.tryParse(_downloadController.text.trim().replaceAll(',', '.'));
    final upload = double.tryParse(_uploadController.text.trim().replaceAll(',', '.'));

    if (widget.existente == null) {
      await _repo.criarLinkDeEscola(
        idLevantamento: widget.idLevantamento,
        inep: widget.inep,
        matricula: widget.matricula,
        operadoraInformada: operadora.isEmpty ? null : operadora,
        velocidadeContratadaInformada: velocidadeContratada.isEmpty ? null : velocidadeContratada,
        velocidadeDownload: download,
        velocidadeUpload: upload,
        idAmbiente: _idAmbiente,
      );
    } else {
      await _repo.atualizarLinkEscola(
        id: widget.existente!.id,
        operadoraInformada: operadora.isEmpty ? null : operadora,
        velocidadeContratadaInformada: velocidadeContratada.isEmpty ? null : velocidadeContratada,
        velocidadeDownload: download,
        velocidadeUpload: upload,
        idAmbiente: _idAmbiente,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    // Só oferece ambientes que ainda existem na lista atual — se o
    // ambiente vinculado antes foi removido, cai em "não informado" em vez
    // de quebrar o dropdown com um value que não está mais nos items.
    final idAmbienteValido = widget.ambientes.any((a) => a.id == _idAmbiente) ? _idAmbiente : null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.existente == null ? 'Internet paga pela escola' : 'Editar link da escola')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        children: [
          const Text(
            'Sem contrato do Estado — o que a escola informar sobre a própria internet ("escola conectada").',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _operadoraController,
            decoration: const InputDecoration(labelText: 'Operadora informada'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _velocidadeContratadaController,
            decoration: const InputDecoration(labelText: 'Velocidade contratada informada (Mbps)'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _downloadController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Medida — download (Mbps)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _uploadController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Medida — upload (Mbps)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: idAmbienteValido,
            decoration: const InputDecoration(labelText: 'Ambiente onde o link fica (opcional)'),
            items: widget.ambientes
                .map((a) => DropdownMenuItem(value: a.id, child: Text(a.nomeAmbiente, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => setState(() => _idAmbiente = v),
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
