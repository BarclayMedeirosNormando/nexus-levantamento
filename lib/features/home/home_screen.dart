import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../../core/route_observer.dart';
import '../../core/theme.dart';
import '../../data/local/escolas_repository.dart';
import '../../data/local/levantamentos_repository.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/auth_service.dart';
import '../../data/sync_engine.dart';
import '../auth/login_screen.dart';
import '../auth/trocar_senha_screen.dart';
import '../catalogo/catalogo_modelos_screen.dart';
import '../escola/escola_detail_screen.dart';
import 'escola_card.dart';
import 'gerenciar_tecnicos_screen.dart';
import 'levantamentos_lista_screen.dart';
import 'regionais_screen.dart';

/// "Minhas Escolas". Dois modos, decididos pelo campo de busca:
/// - **Busca vazia**: navegação em árvore Regional → Município → Escolas
///   (`RegionaisLista`, embutida) — mais fácil de navegar em 647 escolas do
///   que rolar uma lista só.
/// - **Busca preenchida**: lista plana filtrada por nome/INEP/município,
///   ignorando a árvore (a pessoa já sabe o que procura).
///
/// Acima de tudo isso, sempre visível: a linha de cartões-resumo (§5 Tela 2
/// do spec, ampliada 2026-09-12) — "Em andamento", "Concluídos" (só ADM) e
/// "Pendentes de sync", cada um abrindo a lista cheia correspondente (ver
/// `levantamentos_lista_screen.dart`) — o que ficou pra trás ou ainda não
/// subiu pro servidor, sem precisar navegar pela árvore de novo pra achar.
///
/// ESCOLAS é tabela de referência, só leitura no app (ver §4/§9 do spec) —
/// tudo aqui lê do SQLite local, sync é só o botão/ícone pra atualizar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});
  final Session session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  final _syncEngine = SyncEngine();
  final _escolasRepo = EscolasRepository();
  final _levantamentosRepo = LevantamentosRepository();
  final _buscaController = TextEditingController();

  bool _syncing = false;
  bool _carregandoBusca = false;
  bool _carregandoResumo = true;
  String? _erroSync;
  List<Escola> _resultadosBusca = const [];
  List<LevantamentoComEscola> _emAndamento = const [];
  List<LevantamentoComEscola> _concluidos = const [];
  PendenciasResumo? _pendencias;

  StreamSubscription<List<ConnectivityResult>>? _conectividadeSub;
  bool _estavaOffline = false;

  // Muda a cada sync bem-sucedido, pra forçar a árvore de regionais (que
  // carrega uma vez no initState dela) a recarregar com dados novos.
  Key _arvoreKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _buscaController.addListener(_onBuscaChanged);
    _carregarResumo();
    _observarConectividade();
  }

  /// Dispara uma sincronização assim que a conexão volta (2026-09-12) —
  /// sem esperar o próximo ciclo do sync em background (workmanager,
  /// mínimo 15 min imposto pela plataforma), cobrindo o caso mais comum:
  /// o app já está aberto e o Wi-Fi/dados voltam no meio do trabalho. Só
  /// dispara na TRANSIÇÃO offline→online (não a cada evento — alguns
  /// aparelhos disparam `onConnectivityChanged` com frequência mesmo sem
  /// mudança real de conectividade). `mostrarErro: false` porque isso roda
  /// sem o técnico ter pedido — um erro nesse sync automático não precisa
  /// virar um alerta vermelho na tela, só o próximo sync (manual ou
  /// automático) tenta de novo.
  void _observarConectividade() {
    _conectividadeSub = Connectivity().onConnectivityChanged.listen((resultados) {
      final online = resultados.any((r) => r != ConnectivityResult.none);
      if (online && _estavaOffline && !_syncing) {
        _sincronizar(mostrarErro: false);
      }
      _estavaOffline = !online;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _buscaController.removeListener(_onBuscaChanged);
    _buscaController.dispose();
    _conectividadeSub?.cancel();
    super.dispose();
  }

  // Chamado pelo RouteObserver toda vez que voltamos pra Home depois de
  // empilhar outra tela (ex.: abrir uma escola, abrir/continuar um
  // levantamento, voltar da seleção de ambientes) — mantém os cartões-resumo
  // (em andamento/concluídos/pendências) sempre batendo com o que existe
  // agora, sem depender de um botão manual de atualizar.
  @override
  void didPopNext() {
    _carregarResumo();
  }

  /// Carrega os três números dos cartões-resumo da Home (2026-09-12,
  /// pedido do usuário pra deixar a tela inicial "mais funcional"): quantos
  /// levantamentos estão em andamento, quantos concluídos (só ADM enxerga —
  /// mesma regra de visibilidade de sempre) e quantas pendências de sync
  /// (levantamentos com dado não enviado + fotos não enviadas) ainda
  /// existem neste aparelho. Os três são só leitura local — nunca chamam a
  /// rede — então pode rodar toda vez que a Home reaparece sem custo.
  Future<void> _carregarResumo() async {
    // Três leituras SEQUENCIAIS de propósito (não `Future.wait`) — são só
    // consultas locais no SQLite (nunca rede), o custo de encadear é
    // desprezível, e evita qualquer ambiguidade de tipo ao misturar
    // `Future<List<...>>` com `Future<PendenciasResumo>` numa lista só.
    final emAndamento = await _levantamentosRepo.listarEmAndamento(
      matricula: widget.session.matricula,
      isAdm: widget.session.isAdm,
    );
    final concluidos = await _levantamentosRepo.listarConcluidos(
      matricula: widget.session.matricula,
      isAdm: widget.session.isAdm,
    );
    final pendencias = await _syncEngine.contarPendencias();
    if (!mounted) return;
    setState(() {
      _emAndamento = emAndamento;
      _concluidos = concluidos;
      _pendencias = pendencias;
      _carregandoResumo = false;
    });
  }

  void _onBuscaChanged() {
    final termo = _buscaController.text;
    if (termo.trim().isEmpty) {
      setState(() => _resultadosBusca = const []);
      return;
    }
    _buscarEscolas(termo);
  }

  Future<void> _buscarEscolas(String termo) async {
    setState(() => _carregandoBusca = true);
    final lista = await _escolasRepo.listar(busca: termo);
    if (!mounted) return;
    // Evita corrida: só aplica o resultado se a busca ainda for a mesma.
    if (_buscaController.text != termo) return;
    setState(() {
      _resultadosBusca = lista;
      _carregandoBusca = false;
    });
  }

  /// [mostrarErro] fica `false` quando quem chamou foi o listener de
  /// reconectividade (ver [_observarConectividade]) — um sync que ninguém
  /// pediu não precisa virar alerta vermelho na tela se falhar; o botão
  /// manual (padrão `true`) sempre mostra.
  Future<void> _sincronizar({bool mostrarErro = true}) async {
    setState(() {
      _syncing = true;
      _erroSync = null;
    });
    try {
      // Ordem de cada passo importa — ver SyncEngine.sincronizarTudo: fotos
      // pendentes primeiro (pra já ir a URL se der tempo), depois sobe o
      // que este aparelho tem pendente, antes de puxar referência/
      // levantamentos ativos (pra não correr o risco de um pull trazer de
      // volta algo desatualizado por cima do que ainda não tinha sido
      // enviado — ver regra de conflito em LevantamentoSyncService).
      final resultado = await _syncEngine.sincronizarTudo(widget.session);

      if (!mounted) return;
      setState(() => _arvoreKey = UniqueKey());
      if (_buscaController.text.trim().isNotEmpty) {
        await _buscarEscolas(_buscaController.text);
      }
      // Um levantamento onde este usuário foi adicionado como auxiliar por
      // outro técnico só aparece aqui depois desse pull — recarrega pra
      // refletir na hora, sem precisar reabrir a Home. Também atualiza
      // concluídos/pendências, já que um sync bem-sucedido normalmente zera
      // (ou reduz) as pendências mostradas nos cartões.
      await _carregarResumo();

      if (!mounted) return;
      final partes = <String>[];
      if (resultado.push.levantamentosEnviados > 0) {
        partes.add(
          '${resultado.push.levantamentosEnviados} levantamento${resultado.push.levantamentosEnviados == 1 ? '' : 's'} enviado${resultado.push.levantamentosEnviados == 1 ? '' : 's'}',
        );
      }
      if (resultado.pull.levantamentos > 0) {
        partes.add(
          '${resultado.pull.levantamentos} levantamento${resultado.pull.levantamentos == 1 ? '' : 's'} baixado${resultado.pull.levantamentos == 1 ? '' : 's'}',
        );
      }
      if (resultado.fotosEnviadas > 0) {
        partes.add(
          '${resultado.fotosEnviadas} foto${resultado.fotosEnviadas == 1 ? '' : 's'} enviada${resultado.fotosEnviadas == 1 ? '' : 's'}',
        );
      }
      if (partes.isNotEmpty) {
        AppSnackbar.sucesso(context, partes.join(' · '));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (mostrarErro) setState(() => _erroSync = e.message);
    } catch (e) {
      // Qualquer erro fora do ApiException (ex: gravação local) também
      // precisa aparecer — nunca falhar silenciosamente (ver §14 do spec).
      // ignore: avoid_print
      print('Erro inesperado ao sincronizar: $e');
      if (!mounted) return;
      if (mostrarErro) setState(() => _erroSync = 'Erro inesperado: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _sair() async {
    await AuthService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _abrirCatalogoModelos() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CatalogoModelosScreen(session: widget.session)),
    );
  }

  void _abrirTrocarSenha() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TrocarSenhaScreen(session: widget.session)),
    );
  }

  void _abrirGerenciarTecnicos() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GerenciarTecnicosScreen(session: widget.session)),
    );
  }

  void _onMenuSelecionado(String valor) {
    switch (valor) {
      case 'catalogo':
        _abrirCatalogoModelos();
        break;
      case 'trocar_senha':
        _abrirTrocarSenha();
        break;
      case 'gerenciar_tecnicos':
        _abrirGerenciarTecnicos();
        break;
      case 'sair':
        _sair();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final buscando = _buscaController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minhas Escolas'),
        actions: [
          IconButton(
            onPressed: _syncing ? null : _sincronizar,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sincronizar dados',
          ),
          // 2026-09-13: ações menos frequentes (catálogo, trocar senha,
          // gerenciar técnicos — só ADM — e sair) foram pro menu de
          // overflow, pra caber sem apertar a AppBar em tela de celular
          // depois de ter entrado mais uma opção (Gerenciar técnicos).
          PopupMenuButton<String>(
            onSelected: _onMenuSelecionado,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'catalogo',
                child: ListTile(
                  leading: Icon(Icons.inventory_2_outlined),
                  title: Text('Catálogo de Modelos'),
                ),
              ),
              const PopupMenuItem(
                value: 'trocar_senha',
                child: ListTile(
                  leading: Icon(Icons.lock_reset_rounded),
                  title: Text('Trocar minha senha'),
                ),
              ),
              if (widget.session.isAdm)
                const PopupMenuItem(
                  value: 'gerenciar_tecnicos',
                  child: ListTile(
                    leading: Icon(Icons.manage_accounts_outlined),
                    title: Text('Gerenciar técnicos'),
                  ),
                ),
              const PopupMenuItem(
                value: 'sair',
                child: ListTile(leading: Icon(Icons.logout), title: Text('Sair')),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primarySoft,
                  child: Text(
                    widget.session.nome.isNotEmpty ? widget.session.nome[0] : '?',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${widget.session.papel} · matrícula ${widget.session.matricula}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          if (!_carregandoResumo) _buildResumoCards(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _buscaController,
              decoration: InputDecoration(
                hintText: 'Buscar por nome, INEP ou município',
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
          if (!buscando)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: const [
                  Icon(Icons.account_tree_outlined, size: 14, color: AppColors.muted),
                  SizedBox(width: 6),
                  Text('Navegue por Regional → Município', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
          if (_erroSync != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                'Erro ao sincronizar: $_erroSync',
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: buscando
                ? _buildResultadosBusca()
                : RegionaisLista(key: _arvoreKey, session: widget.session),
          ),
        ],
      ),
    );
  }

  /// Cartões-resumo (2026-09-12) — substituem a antiga lista "Levantamentos
  /// em andamento" embutida direto na Home (que só existia quando não-vazia
  /// e mostrava tudo inline, sem limite) por três números sempre visíveis:
  /// em andamento, concluídos (só ADM — mesma regra de sempre) e pendências
  /// de sync. Cada um, quando tem algo, é clicável: os dois primeiros abrem
  /// [LevantamentosListaScreen] com a lista cheia (onde cada item já abre o
  /// levantamento normalmente, igual antes); "Pendentes de sync" dispara o
  /// mesmo sync manual do botão da AppBar — é a ação óbvia pra resolver
  /// aquele número.
  Widget _buildResumoCards() {
    final pendentes = _pendencias?.total ?? 0;

    final cards = <Widget>[
      _ResumoCard(
        icon: Icons.hourglass_top_rounded,
        cor: AppColors.warning,
        rotulo: 'Em andamento',
        valor: _emAndamento.length,
        onTap: _emAndamento.isEmpty
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LevantamentosListaScreen(
                      titulo: 'Em andamento',
                      itens: _emAndamento,
                      session: widget.session,
                    ),
                  ),
                ),
      ),
    ];

    if (widget.session.isAdm) {
      cards.add(
        _ResumoCard(
          icon: Icons.check_circle_outline_rounded,
          cor: AppColors.primary,
          rotulo: 'Concluídos',
          valor: _concluidos.length,
          onTap: _concluidos.isEmpty
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LevantamentosListaScreen(
                        titulo: 'Concluídos',
                        itens: _concluidos,
                        session: widget.session,
                      ),
                    ),
                  ),
        ),
      );
    }

    cards.add(
      _ResumoCard(
        icon: pendentes > 0 ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
        cor: pendentes > 0 ? AppColors.danger : AppColors.muted,
        rotulo: 'Pendentes de sync',
        valor: pendentes,
        onTap: (pendentes > 0 && !_syncing) ? _sincronizar : null,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: cards[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildResultadosBusca() {
    if (_carregandoBusca) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_resultadosBusca.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Nenhuma escola encontrada pra "${_buscaController.text}".',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _buscarEscolas(_buscaController.text.trim()),
      child: FadeIn(
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          itemCount: _resultadosBusca.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final escola = _resultadosBusca[index];
            return EscolaCard(
              escola: escola,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EscolaDetailScreen(escola: escola, session: widget.session),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Um dos cartões da linha-resumo do topo da Home (ver
/// `_HomeScreenState._buildResumoCards`) — só apresentação, sem estado
/// próprio. `onTap` nulo desabilita visualmente o toque (não faz sentido
/// abrir uma lista vazia).
class _ResumoCard extends StatelessWidget {
  const _ResumoCard({
    required this.icon,
    required this.cor,
    required this.rotulo,
    required this.valor,
    required this.onTap,
  });

  final IconData icon;
  final Color cor;
  final String rotulo;
  final int valor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cor.withOpacity(0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: cor),
            const SizedBox(height: 4),
            Text(
              '$valor',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink),
            ),
            const SizedBox(height: 2),
            Text(
              rotulo,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: AppColors.muted, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
