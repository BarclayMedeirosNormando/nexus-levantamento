import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/levantamento_sync_service.dart';
import '../../data/local/levantamentos_repository.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/auth_service.dart';
import '../levantamento/levantamento_screen.dart';

/// Lista cheia de levantamentos por status (2026-09-12) — aberta pelos
/// cartões-resumo "Em andamento"/"Concluídos" da Home (ver
/// `home_screen.dart`), pra não precisar espremer tudo inline na tela
/// principal (que só mostrava "em andamento", sem nunca ter tido uma visão
/// de concluídos). Cada item abre o mesmo `LevantamentoScreen` de sempre —
/// não existe uma tela de "visualização" separada.
///
/// Reabrir (2026-09-14) — só ADM, só nos concluídos (ver `_ItemCard`):
/// pedido do Barclay depois de notar que o backend já tinha
/// `reabrir_levantamento` pronto, mas nenhuma tela chamava. Precisou virar
/// StatefulWidget (antes era Stateless recebendo `itens` fixo da Home) pra
/// poder tirar o item da lista na hora, sem esperar a Home recarregar.
class LevantamentosListaScreen extends StatefulWidget {
  const LevantamentosListaScreen({
    super.key,
    required this.titulo,
    required this.itens,
    required this.session,
  });

  final String titulo;
  final List<LevantamentoComEscola> itens;
  final Session session;

  @override
  State<LevantamentosListaScreen> createState() => _LevantamentosListaScreenState();
}

class _LevantamentosListaScreenState extends State<LevantamentosListaScreen> {
  late final List<LevantamentoComEscola> _itens = List.of(widget.itens);
  final _buscaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _buscaController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _removerDaLista(LevantamentoComEscola item) {
    setState(() => _itens.remove(item));
  }

  // Busca por nome da escola ou município (2026-09-14, pedido do Barclay):
  // a lista de concluídos pode chegar a centenas (ver
  // LevantamentosRepository.listarConcluidos, capado em 300) — sem isso só
  // dava pra achar uma escola específica rolando a lista inteira.
  List<LevantamentoComEscola> get _itensFiltrados {
    final termo = _buscaController.text.trim().toLowerCase();
    if (termo.isEmpty) return _itens;
    return _itens.where((i) {
      final nome = i.escola.nome.toLowerCase();
      final municipio = (i.escola.municipio ?? '').toLowerCase();
      return nome.contains(termo) || municipio.contains(termo);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visiveis = _itensFiltrados;
    final buscando = _buscaController.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.titulo} (${_itens.length})')),
      body: Column(
        children: [
          if (_itens.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _buscaController,
                decoration: InputDecoration(
                  hintText: 'Buscar por escola ou município',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: buscando
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _buscaController.clear,
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                ),
              ),
            ),
          Expanded(
            child: visiveis.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        buscando ? 'Nenhuma escola encontrada pra "${_buscaController.text}".' : 'Nada por aqui.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ),
                  )
                : FadeIn(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      itemCount: visiveis.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = visiveis[index];
                        return _ItemCard(
                          item: item,
                          session: widget.session,
                          onReaberto: () => _removerDaLista(item),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatefulWidget {
  const _ItemCard({required this.item, required this.session, required this.onReaberto});
  final LevantamentoComEscola item;
  final Session session;
  final VoidCallback onReaberto;

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  final _syncService = LevantamentoSyncService();
  bool _reabrindo = false;

  bool get _concluido => widget.item.levantamento.status == 'concluido';

  Future<void> _abrirLevantamento() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LevantamentoScreen(
          escola: widget.item.escola,
          levantamento: widget.item.levantamento,
          session: widget.session,
        ),
      ),
    );
  }

  // Pede a senha do próprio ADM logado (matrícula já vem preenchida — é
  // sempre quem está com a sessão aberta, mesma exigência do backend) e
  // chama reabrirLevantamento. Diálogo simples (AlertDialog), mesmo padrão
  // já usado em WifiScreen/ConectividadeFormEscolaScreen pra senha com
  // botão de mostrar/esconder.
  Future<void> _confirmarReabertura() async {
    final senhaController = TextEditingController();
    var senhaVisivel = false;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Reabrir levantamento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.item.escola.nome} volta para "Em andamento". '
                'Confirme sua senha de ADM (matrícula ${widget.session.matricula}) para continuar.',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: senhaController,
                autofocus: true,
                obscureText: !senhaVisivel,
                decoration: InputDecoration(
                  labelText: 'Sua senha',
                  suffixIcon: IconButton(
                    icon: Icon(senhaVisivel ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                    onPressed: () => setDialogState(() => senhaVisivel = !senhaVisivel),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Reabrir')),
          ],
        ),
      ),
    );
    if (confirmou != true || !mounted) return;

    final senha = senhaController.text;
    if (senha.isEmpty) {
      AppSnackbar.aviso(context, 'Informe sua senha.');
      return;
    }

    setState(() => _reabrindo = true);
    try {
      await _syncService.reabrirLevantamento(
        idLevantamento: widget.item.levantamento.id,
        matriculaAdm: widget.session.matricula,
        senhaAdm: senha,
      );
      if (!mounted) return;
      AppSnackbar.sucesso(context, '${widget.item.escola.nome} reaberto — voltou para "Em andamento".');
      widget.onReaberto();
    } on ApiException catch (e) {
      if (!mounted) return;
      AppSnackbar.erro(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.erro(context, 'Erro inesperado: $e');
    } finally {
      if (mounted) setState(() => _reabrindo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final concluido = _concluido;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _abrirLevantamento,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            StatusLevantamentoChip(concluido: concluido),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.escola.nome,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.item.escola.municipio != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        widget.item.escola.municipio!,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ),
                  if (widget.session.isAdm && widget.item.levantamento.tecnicoAbertura.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Técnico: ${widget.item.levantamento.tecnicoAbertura}',
                        style: const TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ),
                ],
              ),
            ),
            if (concluido && widget.session.isAdm)
              TextButton.icon(
                onPressed: _reabrindo ? null : _confirmarReabertura,
                icon: _reabrindo
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.lock_open_rounded, size: 16),
                label: const Text('Reabrir'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              )
            else
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
