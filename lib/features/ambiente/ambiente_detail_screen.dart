import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/ambientes_repository.dart';
import '../../data/local/equipamentos_repository.dart';
import '../../data/remote/auth_service.dart';
import '../levantamento/catalogo_picker_sheet.dart';
import '../levantamento/equipamento_form_screen.dart';
import '../levantamento/inservivel_form_screen.dart';

/// Detalhe do Ambiente — Tela 5 do spec: cadastro de Equipamentos e
/// Inservíveis dentro do ambiente, além de renomeá-lo (pedido do usuário:
/// vários ambientes já criados em campo com nome errado/provisório não
/// tinham como ser corrigidos, só recriados do zero).
///
/// "Novo equipamento" segue o fluxo "catálogo primeiro" pedido: abre a busca
/// no catálogo (showCatalogoPickerSheet) antes do formulário — se a pessoa
/// escolher um item, o formulário já abre preenchido; se escolher "Digitar
/// sem catálogo", abre em branco igual sempre foi; se cancelar, não abre
/// nada.
class AmbienteDetailScreen extends StatefulWidget {
  const AmbienteDetailScreen({
    super.key,
    required this.ambiente,
    required this.idLevantamento,
    required this.inep,
    required this.session,
  });
  final Ambiente ambiente;
  final String idLevantamento;
  final String inep;
  final Session session;

  @override
  State<AmbienteDetailScreen> createState() => _AmbienteDetailScreenState();
}

class _AmbienteDetailScreenState extends State<AmbienteDetailScreen> {
  final _ambientesRepo = AmbientesRepository();
  final _equipamentosRepo = EquipamentosRepository();

  late String _nome = widget.ambiente.nomeAmbiente;
  bool _renomeando = false;
  bool _carregando = true;
  List<Equipamento> _equipamentos = const [];
  List<EquipamentoInservivel> _inserviveis = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final equipamentos = await _equipamentosRepo.listarPorAmbiente(widget.ambiente.id);
    final inserviveis = await _equipamentosRepo.listarInserviveisPorAmbiente(widget.ambiente.id);
    if (!mounted) return;
    setState(() {
      _equipamentos = equipamentos;
      _inserviveis = inserviveis;
      _carregando = false;
    });
  }

  Future<void> _renomear() async {
    final controller = TextEditingController(text: _nome);
    final novoNome = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Renomear ambiente'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Nome do ambiente'),
          onSubmitted: (v) {
            final texto = v.trim();
            if (texto.isNotEmpty) Navigator.of(dialogContext).pop(texto);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final texto = controller.text.trim();
              if (texto.isEmpty) return;
              Navigator.of(dialogContext).pop(texto);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (novoNome == null || novoNome == _nome) return;
    setState(() => _renomeando = true);
    await _ambientesRepo.renomear(id: widget.ambiente.id, novoNome: novoNome);
    if (!mounted) return;
    setState(() {
      _nome = novoNome;
      _renomeando = false;
    });
  }

  Future<void> _abrirNovoEquipamento() async {
    final resultado = await showCatalogoPickerSheet(context: context, session: widget.session);
    if (resultado == null || !mounted) return;

    final salvou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EquipamentoFormScreen(
          idAmbiente: widget.ambiente.id,
          idLevantamento: widget.idLevantamento,
          inep: widget.inep,
          session: widget.session,
          catalogoInicial: resultado.item,
        ),
      ),
    );
    if (salvou == true) await _carregar();
  }

  Future<void> _abrirEditarEquipamento(Equipamento equipamento) async {
    final salvou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EquipamentoFormScreen(
          idAmbiente: widget.ambiente.id,
          idLevantamento: widget.idLevantamento,
          inep: widget.inep,
          session: widget.session,
          existente: equipamento,
        ),
      ),
    );
    if (salvou == true) await _carregar();
  }

  Future<void> _duplicarEquipamento(Equipamento equipamento) async {
    await _equipamentosRepo.duplicar(equipamento.id, matricula: widget.session.matricula);
    await _carregar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Equipamento duplicado — complete Tombamento e Nº de Série.')),
    );
  }

  Future<void> _removerEquipamento(Equipamento equipamento) async {
    final confirmou = await _confirmarRemocao(titulo: 'Remover equipamento?');
    if (confirmou != true) return;
    await _equipamentosRepo.remover(equipamento.id);
    await _carregar();
  }

  Future<void> _abrirNovoInservivel() async {
    final salvou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => InservivelFormScreen(
          idAmbiente: widget.ambiente.id,
          idLevantamento: widget.idLevantamento,
          inep: widget.inep,
          matricula: widget.session.matricula,
        ),
      ),
    );
    if (salvou == true) await _carregar();
  }

  Future<void> _abrirEditarInservivel(EquipamentoInservivel inservivel) async {
    final salvou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => InservivelFormScreen(
          idAmbiente: widget.ambiente.id,
          idLevantamento: widget.idLevantamento,
          inep: widget.inep,
          matricula: widget.session.matricula,
          existente: inservivel,
        ),
      ),
    );
    if (salvou == true) await _carregar();
  }

  Future<void> _removerInservivel(EquipamentoInservivel inservivel) async {
    final confirmou = await _confirmarRemocao(titulo: 'Remover inservível?');
    if (confirmou != true) return;
    await _equipamentosRepo.removerInservivel(inservivel.id);
    await _carregar();
  }

  // Mesmo caveat já usado na remoção de auxiliar (GerenciarAuxiliaresScreen):
  // remover aqui é só local — o backend nunca apaga linha nenhuma
  // (upsertRows só adiciona/atualiza), então um item já sincronizado antes
  // pode voltar a aparecer numa próxima sincronização vinda de outro
  // aparelho.
  Future<bool?> _confirmarRemocao({required String titulo}) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(titulo),
        content: const Text(
          'Isso remove só deste aparelho. Se esse item já tiver sido sincronizado antes, '
          'ele pode voltar a aparecer aqui numa próxima sincronização.',
        ),
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
  }

  Future<void> _abrirOpcoesAdicionar() async {
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
                  'Adicionar',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.devices_outlined, color: AppColors.primary),
              title: const Text('Equipamento'),
              subtitle: const Text('Em uso, funcionando', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              onTap: () => Navigator.of(sheetContext).pop('equipamento'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined, color: AppColors.primary),
              title: const Text('Inservível'),
              subtitle: const Text('Sucateado, fora de uso', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              onTap: () => Navigator.of(sheetContext).pop('inservivel'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (opcao == 'equipamento') {
      await _abrirNovoEquipamento();
    } else if (opcao == 'inservivel') {
      await _abrirNovoInservivel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_nome),
        actions: [
          IconButton(
            onPressed: _renomeando ? null : _renomear,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Renomear ambiente',
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: [
                Text(
                  widget.ambiente.origem == 'padrao' ? 'AMBIENTE PADRÃO' : 'AMBIENTE AVULSO',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),
                _SectionHeader(titulo: 'Equipamentos', contagem: _equipamentos.length),
                const SizedBox(height: 8),
                if (_equipamentos.isEmpty)
                  const _EmptyHint(texto: 'Nenhum equipamento cadastrado ainda.')
                else
                  ..._equipamentos.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _EquipamentoCard(
                        equipamento: e,
                        onTap: () => _abrirEditarEquipamento(e),
                        onDuplicar: () => _duplicarEquipamento(e),
                        onRemover: () => _removerEquipamento(e),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                _SectionHeader(titulo: 'Inservíveis', contagem: _inserviveis.length),
                const SizedBox(height: 8),
                if (_inserviveis.isEmpty)
                  const _EmptyHint(texto: 'Nenhum inservível cadastrado ainda.')
                else
                  ..._inserviveis.map(
                    (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _InservivelCard(
                        inservivel: i,
                        onTap: () => _abrirEditarInservivel(i),
                        onRemover: () => _removerInservivel(i),
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: _carregando
          ? null
          : FloatingActionButton.extended(
              onPressed: _abrirOpcoesAdicionar,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar'),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.titulo, required this.contagem});
  final String titulo;
  final int contagem;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink)),
        const SizedBox(width: 8),
        if (contagem > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(999)),
            child: Text(
              '$contagem',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary),
            ),
          ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.texto});
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Text(texto, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
    );
  }
}

class _EquipamentoCard extends StatelessWidget {
  const _EquipamentoCard({
    required this.equipamento,
    required this.onTap,
    required this.onDuplicar,
    required this.onRemover,
  });
  final Equipamento equipamento;
  final VoidCallback onTap;
  final VoidCallback onDuplicar;
  final VoidCallback onRemover;

  @override
  Widget build(BuildContext context) {
    final subtitulo = [
      if (equipamento.marca != null && equipamento.marca!.isNotEmpty) equipamento.marca,
      if (equipamento.modeloExibido.isNotEmpty) equipamento.modeloExibido,
    ].join(' · ');
    final identificacao = [
      if (equipamento.tombamento != null && equipamento.tombamento!.isNotEmpty) 'Tomb. ${equipamento.tombamento}',
      if (equipamento.numSerie != null && equipamento.numSerie!.isNotEmpty) 'Série ${equipamento.numSerie}',
    ].join(' · ');

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
              child: const Icon(Icons.devices_outlined, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    equipamento.tipoEquipamento,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink),
                  ),
                  if (subtitulo.isNotEmpty)
                    Text(subtitulo, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  if (identificacao.isNotEmpty)
                    Text(identificacao, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy_outlined, size: 18, color: AppColors.muted),
              tooltip: 'Duplicar',
              onPressed: onDuplicar,
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

class _InservivelCard extends StatelessWidget {
  const _InservivelCard({required this.inservivel, required this.onTap, required this.onRemover});
  final EquipamentoInservivel inservivel;
  final VoidCallback onTap;
  final VoidCallback onRemover;

  @override
  Widget build(BuildContext context) {
    final subtitulo = [
      if (inservivel.marca != null && inservivel.marca!.isNotEmpty) inservivel.marca,
      if (inservivel.modelo != null && inservivel.modelo!.isNotEmpty) inservivel.modelo,
    ].join(' · ');

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
              child: const Icon(Icons.delete_sweep_outlined, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    inservivel.tipoEquipamento,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink),
                  ),
                  if (subtitulo.isNotEmpty)
                    Text(subtitulo, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  Text(
                    'Quantidade: ${inservivel.quantidade}',
                    style: const TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
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
