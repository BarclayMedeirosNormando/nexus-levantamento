import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import '../../core/theme.dart';
import '../../data/local/ambientes_repository.dart';
import '../../data/local/conectividade_repository.dart';
import '../../data/local/equipamentos_repository.dart';
import '../../data/local/escolas_repository.dart';
import '../../data/local/levantamentos_repository.dart';
import '../../data/local/servidores_repository.dart';
import '../../data/levantamento_sync_service.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/auth_service.dart';
import 'servidor_picker_sheet.dart';

/// Tela 8 do spec — passo final do levantamento: checklist automático de
/// pendências óbvias (não bloqueia, só avisa — "não deixa concluir com
/// pendência óbvia sem pelo menos um aviso explícito"), escolha do
/// Servidor responsável pela assinatura (busca por matrícula ou nome em
/// TODOS os servidores sincronizados — ver decisão de 2026-09-12 em
/// `ServidoresRepository.buscar`, não é mais restrito a quem tem
/// PODE_ASSINAR=true) e assinatura no canvas (`signature` pkg). Ao confirmar: sobe a assinatura pro Drive
/// (`upload_assinatura` — mesmo endpoint que já existia no backend sem
/// nunca ter sido chamado pelo app, ver §9 do spec), grava STATUS=concluido
/// localmente (LevantamentosRepository.concluir) e sincroniza na hora
/// (`LevantamentoSyncService.pushPendentes` — "entra na fila de sync com
/// prioridade" do spec vira, na prática, "sobe imediatamente" em vez de
/// esperar o próximo toque manual em "Sincronizar").
///
/// AÇÃO ONLINE-ONLY: precisa de internet pra concluir (o upload da
/// assinatura não tem fila offline própria ainda — ver pendência de
/// upload de foto no §9 do spec, mesma limitação). Sem internet, mostra
/// erro e não conclui; a pessoa tenta de novo quando tiver sinal.
class ConclusaoScreen extends StatefulWidget {
  const ConclusaoScreen({
    super.key,
    required this.escola,
    required this.levantamento,
    required this.session,
  });
  final Escola escola;
  final Levantamento levantamento;
  final Session session;

  @override
  State<ConclusaoScreen> createState() => _ConclusaoScreenState();
}

class _ConclusaoScreenState extends State<ConclusaoScreen> {
  final _ambientesRepo = AmbientesRepository();
  final _equipamentosRepo = EquipamentosRepository();
  final _conectividadeRepo = ConectividadeRepository();
  final _levantamentosRepo = LevantamentosRepository();
  final _syncService = LevantamentoSyncService();
  final _api = ApiClient();

  final _signatureController = SignatureController(penStrokeWidth: 3, penColor: Colors.black);

  bool _carregando = true;
  bool _concluindo = false;
  String? _erro;

  bool _semAmbienteNenhum = false;
  List<String> _ambientesSemNada = const [];
  bool _semConectividade = false;
  ServidorAssinante? _responsavel;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final ambientes = await _ambientesRepo.listarPorLevantamento(widget.levantamento.id);
    final vazios = <String>[];
    for (final ambiente in ambientes) {
      final equipamentos = await _equipamentosRepo.listarPorAmbiente(ambiente.id);
      if (equipamentos.isNotEmpty) continue;
      final inserviveis = await _equipamentosRepo.listarInserviveisPorAmbiente(ambiente.id);
      if (inserviveis.isEmpty) vazios.add(ambiente.nomeAmbiente);
    }
    final conectividade = await _conectividadeRepo.listarPorLevantamento(widget.levantamento.id);

    if (!mounted) return;
    setState(() {
      _semAmbienteNenhum = ambientes.isEmpty;
      _ambientesSemNada = vazios;
      _semConectividade = conectividade.isEmpty;
      _carregando = false;
    });
  }

  Future<void> _abrirPickerResponsavel() async {
    final escolhido = await showServidorPickerSheet(context: context, session: widget.session);
    if (escolhido == null || !mounted) return;
    setState(() {
      _responsavel = escolhido;
      _erro = null;
    });
  }

  List<String> get _pendencias => [
        if (_semAmbienteNenhum) 'Nenhum ambiente cadastrado ainda.',
        if (!_semAmbienteNenhum && _ambientesSemNada.isNotEmpty)
          '${_ambientesSemNada.length} ambiente${_ambientesSemNada.length == 1 ? '' : 's'} sem nenhum equipamento ou inservível: ${_ambientesSemNada.join(', ')}.',
        if (_semConectividade) 'Conectividade não preenchida.',
      ];

  Future<void> _concluir() async {
    if (_responsavel == null) {
      setState(() => _erro = 'Escolha o servidor responsável pela assinatura.');
      return;
    }
    if (_signatureController.isEmpty) {
      setState(() => _erro = 'Assine no campo acima antes de concluir.');
      return;
    }

    if (_pendencias.isNotEmpty) {
      final continuar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Concluir mesmo assim?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ainda há pendências neste levantamento:'),
                const SizedBox(height: 8),
                for (final p in _pendencias) Text('• $p', style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Voltar e corrigir')),
            ElevatedButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Concluir mesmo assim')),
          ],
        ),
      );
      if (continuar != true) return;
    }

    setState(() {
      _concluindo = true;
      _erro = null;
    });

    try {
      final bytes = await _signatureController.toPngBytes();
      if (bytes == null) {
        throw ApiException('Não foi possível capturar a assinatura. Tente assinar de novo.');
      }

      final resposta = await _api.call('upload_assinatura', {
        'token': widget.session.token,
        'base64': base64Encode(bytes),
        'nome_arquivo': 'assinatura_${widget.levantamento.id}.png',
        'mime_type': 'image/png',
      });
      if (resposta['ok'] != true) {
        throw ApiException(resposta['error']?.toString() ?? 'Não foi possível enviar a assinatura.');
      }
      final url = resposta['url']?.toString();
      if (url == null || url.isEmpty) {
        throw ApiException('Servidor não devolveu o link da assinatura.');
      }

      await _levantamentosRepo.concluir(
        idLevantamento: widget.levantamento.id,
        idServidorResponsavel: _responsavel!.matricula,
        assinaturaUrl: url,
      );

      // "Entra na fila de sync com prioridade" (spec) — sobe na hora em vez
      // de esperar o próximo "Sincronizar" manual na Home. Se essa etapa
      // falhar (rede caiu bem nesse instante), o levantamento já está
      // concluído localmente e com sync_status='pending' — sobe sozinho no
      // próximo sync manual, não fica perdido.
      await _syncService.pushPendentes(widget.session);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _concluindo = false;
        _erro = 'Precisa de internet pra concluir (${e.message}).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _concluindo = false;
        _erro = 'Não foi possível concluir: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Concluir levantamento')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              children: [
                _ChecklistCard(pendencias: _pendencias),
                const SizedBox(height: 20),
                const Text('RESPONSÁVEL PELA ASSINATURA', style: _labelStyle),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _abrirPickerResponsavel,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      hintText: 'Buscar por matrícula ou nome...',
                      prefixIcon: Icon(Icons.search),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                    child: Text(
                      _responsavel == null
                          ? 'Buscar por matrícula ou nome...'
                          : '${_responsavel!.nome} (${_responsavel!.matricula})',
                      style: _responsavel == null
                          ? const TextStyle(color: AppColors.muted)
                          : const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text('ASSINATURA', style: _labelStyle),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setState(() => _signatureController.clear()),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Limpar'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Signature(controller: _signatureController, backgroundColor: Colors.white),
                ),
                if (_erro != null) ...[
                  const SizedBox(height: 16),
                  Text(_erro!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
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
                    onPressed: _concluindo ? null : _concluir,
                    icon: _concluindo
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_outline, size: 20),
                    label: Text(_concluindo ? 'Concluindo...' : 'Concluir levantamento'),
                  ),
                ),
              ),
            ),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({required this.pendencias});
  final List<String> pendencias;

  @override
  Widget build(BuildContext context) {
    final ok = pendencias.isEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ok ? AppColors.success.withOpacity(0.08) : AppColors.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ok ? AppColors.success : AppColors.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                color: ok ? AppColors.success : AppColors.warning,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                ok ? 'Nenhuma pendência óbvia encontrada' : 'Pendências encontradas',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.ink),
              ),
            ],
          ),
          if (!ok) ...[
            const SizedBox(height: 8),
            for (final p in pendencias)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $p', style: const TextStyle(fontSize: 12, color: AppColors.ink)),
              ),
          ],
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
