import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/levantamento_sync_service.dart';
import '../../data/local/ambientes_repository.dart';
import '../../data/local/auxiliares_repository.dart';
import '../../data/local/conectividade_repository.dart';
import '../../data/local/escolas_repository.dart';
import '../../data/local/fotos_levantamento_repository.dart';
import '../../data/local/levantamentos_repository.dart';
import '../../data/local/wifi_repository.dart';
import '../../data/remote/auth_service.dart';
import '../ambiente/ambiente_detail_screen.dart';
import 'adicionar_ambiente_screen.dart';
import 'conectividade_screen.dart';
import 'gerenciar_auxiliares_screen.dart';
import 'conclusao_screen.dart';
import 'fotos_levantamento_screen.dart';
import 'wifi_screen.dart';

/// Levantamento aberto (em_andamento). DATA_INICIO e LAT/LONG_ABERTURA já
/// são capturados na abertura (feito antes de chegar aqui — ver
/// EscolaDetailScreen). Esta tela cobre a Tela 4 do spec: se o levantamento
/// ainda não tem nenhum AMBIENTE criado, mostra a seleção inicial (checklist
/// de AMBIENTES_PADRAO, os `OBRIGATORIO=true` pré-marcados); depois disso
/// (ou pulando a seleção), mostra a lista de ambientes já criados, com
/// "Adicionar ambiente" sempre disponível pra completar depois.
class LevantamentoScreen extends StatefulWidget {
  const LevantamentoScreen({
    super.key,
    required this.escola,
    required this.levantamento,
    required this.session,
  });
  final Escola escola;
  final Levantamento levantamento;
  final Session session;

  @override
  State<LevantamentoScreen> createState() => _LevantamentoScreenState();
}

class _LevantamentoScreenState extends State<LevantamentoScreen> {
  final _ambientesRepo = AmbientesRepository();
  final _auxiliaresRepo = AuxiliaresRepository();
  final _wifiRepo = WifiRepository();
  final _conectividadeRepo = ConectividadeRepository();
  final _fotosRepo = FotosLevantamentoRepository();
  final _levantamentosRepo = LevantamentosRepository();
  final _syncService = LevantamentoSyncService();

  bool _carregando = true;
  bool _salvando = false;
  List<AmbientePadrao> _ambientesPadrao = const [];
  List<Ambiente> _ambientesCriados = const [];
  List<TecnicoOpcao> _auxiliares = const [];
  int _qtdWifi = 0;
  int _qtdConectividade = 0;
  int _qtdFotos = 0;
  final Set<String> _selecionados = {};

  // Já começa com o valor vindo do banco (relevante ao "continuar" um
  // levantamento que já passou por essa etapa antes); vira `true` também
  // ao confirmar a seleção inicial nesta sessão (ver _confirmarSelecaoInicial).
  late bool _selecaoAmbientesFeita = widget.levantamento.ambientesSelecaoFeita;

  // Sync "quase em tempo real" (2026-09-13) — pedido do Barclay: quando um
  // técnico cria os ambientes, os auxiliares precisam ver isso pra poder
  // começar a cadastrar equipamento, e esperar o sync de 15 em 15 min (ou
  // alguém lembrar de tocar em "Sincronizar") demorava demais em campo.
  // Timer só ativo enquanto ESTA tela está aberta — busca a cada 25s se
  // algo novo chegou pra este levantamento (ambiente/equipamento criado por
  // outro auxiliar). Chama só `pull_levantamentos_ativos` (o backend já
  // filtra pra só este(s) levantamento(s), ver `linhasPorLevantamento` em
  // backend_levantamento.gs) — NUNCA o `pull_referencia` pesado, que seria
  // exagero rodar a cada 25s. Silencioso de propósito: sem rede, só não
  // atualiza nada até a próxima tentativa, nunca interrompe o uso da tela.
  Timer? _pollTimer;
  bool _atualizandoEmSegundoPlano = false;

  @override
  void initState() {
    super.initState();
    _carregar();
    _pollTimer = Timer.periodic(const Duration(seconds: 25), (_) => _atualizarEmSegundoPlano());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _atualizarEmSegundoPlano() async {
    if (_atualizandoEmSegundoPlano || !mounted) return;
    _atualizandoEmSegundoPlano = true;
    try {
      await _syncService.pullLevantamentosAtivos(widget.session);
      if (!mounted) return;
      await _recarregarAmbientesCriados();
      await _recarregarContadores();
    } catch (_) {
      // Sem rede ou erro passageiro — tenta de novo no próximo ciclo (25s).
    } finally {
      _atualizandoEmSegundoPlano = false;
    }
  }

  // Sobe este levantamento pro servidor na hora, em vez de esperar o
  // próximo sync completo (manual, ao reconectar, ou o automático de 15 em
  // 15 min) — é o outro lado do mesmo pedido: sem isso, o ambiente ficava
  // `pending` neste aparelho até um desses gatilhos, e só DEPOIS disso o
  // auxiliar (com o polling acima) tinha algo novo pra baixar. Best-effort
  // e silencioso: se não tiver rede agora, o registro continua `pending` e
  // sobe sozinho no próximo sync de qualquer forma — não é uma falha que
  // precise aparecer pro usuário.
  void _pushImediato() {
    unawaited(_syncService.pushPendentes(widget.session).catchError((_) {
      return const PushResult(levantamentosEnviados: 0, avisos: []);
    }));
  }

  Future<void> _carregar() async {
    final padrao = await _ambientesRepo.listarPadrao();
    final criados = await _ambientesRepo.listarPorLevantamento(widget.levantamento.id);
    final auxiliares = await _auxiliaresRepo.listarAuxiliares(widget.levantamento.id);
    final wifi = await _wifiRepo.listarPorLevantamento(widget.levantamento.id);
    final conectividade = await _conectividadeRepo.listarPorLevantamento(widget.levantamento.id);
    final fotos = await _fotosRepo.listarPorLevantamento(widget.levantamento.id);
    if (!mounted) return;
    setState(() {
      _ambientesPadrao = padrao;
      _ambientesCriados = criados;
      _auxiliares = auxiliares;
      _qtdWifi = wifi.length;
      _qtdConectividade = conectividade.length;
      _qtdFotos = fotos.length;
      // Pré-marca os obrigatórios só na primeira carga (lista de criados
      // ainda vazia) — se já existem ambientes, essa seleção não é mais
      // relevante (a tela já vai direto pra lista).
      if (criados.isEmpty) {
        _selecionados
          ..clear()
          ..addAll(padrao.where((p) => p.obrigatorio).map((p) => p.idTipoAmbiente));
      }
      _carregando = false;
    });
  }

  Future<void> _recarregarAuxiliares() async {
    final auxiliares = await _auxiliaresRepo.listarAuxiliares(widget.levantamento.id);
    if (!mounted) return;
    setState(() => _auxiliares = auxiliares);
  }

  Future<void> _recarregarAmbientesCriados() async {
    final criados = await _ambientesRepo.listarPorLevantamento(widget.levantamento.id);
    if (!mounted) return;
    setState(() => _ambientesCriados = criados);
  }

  // Mesma ideia do de cima, só que pros contadores mostrados como bolinha
  // nos ícones de Fotos/Wifi/Conectividade da AppBar (ver _iconeComContador)
  // — chamado ao voltar de cada uma dessas telas e no poll de 25s, pra
  // refletir o que outro auxiliar cadastrou também.
  Future<void> _recarregarContadores() async {
    final wifi = await _wifiRepo.listarPorLevantamento(widget.levantamento.id);
    final conectividade = await _conectividadeRepo.listarPorLevantamento(widget.levantamento.id);
    final fotos = await _fotosRepo.listarPorLevantamento(widget.levantamento.id);
    if (!mounted) return;
    setState(() {
      _qtdWifi = wifi.length;
      _qtdConectividade = conectividade.length;
      _qtdFotos = fotos.length;
    });
  }

  Future<void> _confirmarSelecaoInicial({bool pular = false}) async {
    setState(() => _salvando = true);
    var criouAlgo = false;
    if (!pular && _selecionados.isNotEmpty) {
      final selecionados = _ambientesPadrao.where((p) => _selecionados.contains(p.idTipoAmbiente)).toList();
      await _ambientesRepo.criarEmLote(
        idLevantamento: widget.levantamento.id,
        inep: widget.escola.inep,
        matricula: widget.session.matricula,
        selecionados: selecionados,
      );
      criouAlgo = true;
    }
    // Marca a etapa como concluída sempre — inclusive ao pular — senão,
    // sem nenhum ambiente criado, a tela não teria como saber que a
    // seleção já foi decidida e voltaria a mostrar o checklist pra sempre.
    await _levantamentosRepo.marcarSelecaoAmbientesFeita(widget.levantamento.id);
    await _recarregarAmbientesCriados();
    if (criouAlgo) _pushImediato();
    if (!mounted) return;
    setState(() {
      _salvando = false;
      _selecaoAmbientesFeita = true;
    });
  }

  // Tela cheia (não bottom sheet) — dá pra marcar vários ambientes padrão
  // de uma vez, igual à seleção inicial, e evita o bottom sheet estourar a
  // altura da janela quando a lista de restantes é grande (bug relatado:
  // "BOTTOM OVERFLOWED").
  Future<void> _abrirAdicionarAmbiente() async {
    final jaCriadosTipos = _ambientesCriados.map((a) => a.idTipoAmbiente).whereType<String>().toSet();
    final restantes = _ambientesPadrao.where((p) => !jaCriadosTipos.contains(p.idTipoAmbiente)).toList();

    final criouAlgo = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AdicionarAmbienteScreen(
          idLevantamento: widget.levantamento.id,
          inep: widget.escola.inep,
          matricula: widget.session.matricula,
          padraoRestantes: restantes,
        ),
      ),
    );
    if (criouAlgo == true) {
      await _recarregarAmbientesCriados();
      _pushImediato();
    }
  }

  // Tela cheia (não bottom sheet) — dá pra marcar/desmarcar vários técnicos
  // de uma vez (adicionar E remover) e confirmar tudo junto, igual ao
  // padrão já usado em "Adicionar ambiente" (bug relatado: só dava pra
  // colocar ou tirar um técnico por vez, cada toque já confirmava sozinho).
  Future<void> _abrirGerenciarAuxiliares() async {
    final mudou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GerenciarAuxiliaresScreen(
          idLevantamento: widget.levantamento.id,
          matriculaDono: widget.levantamento.tecnicoAbertura,
        ),
      ),
    );
    if (mudou == true) {
      await _recarregarAuxiliares();
    }
  }

  Future<void> _abrirAmbiente(Ambiente ambiente) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AmbienteDetailScreen(
          ambiente: ambiente,
          idLevantamento: widget.levantamento.id,
          inep: widget.escola.inep,
          session: widget.session,
        ),
      ),
    );
    // Recarrega sempre ao voltar — cobre o caso de ter renomeado o
    // ambiente lá dentro (a lista aqui mostra o nome, precisa refletir), e
    // também os equipamentos cadastrados dentro dele (a contagem exibida
    // no card precisa refletir).
    await _recarregarAmbientesCriados();
  }

  Future<void> _abrirConectividade() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConectividadeScreen(
          escola: widget.escola,
          levantamento: widget.levantamento,
          ambientes: _ambientesCriados,
          matricula: widget.session.matricula,
        ),
      ),
    );
    await _recarregarContadores();
  }

  Future<void> _abrirWifi() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WifiScreen(
          escola: widget.escola,
          levantamento: widget.levantamento,
          matricula: widget.session.matricula,
        ),
      ),
    );
    await _recarregarContadores();
  }

  Future<void> _abrirFotos() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FotosLevantamentoScreen(
          escola: widget.escola,
          levantamento: widget.levantamento,
          matricula: widget.session.matricula,
        ),
      ),
    );
    await _recarregarContadores();
  }

  Future<void> _abrirConclusao() async {
    final prosseguir = await _confirmarRevisaoAntesDeConcluir();
    if (prosseguir != true || !mounted) return;

    final concluido = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ConclusaoScreen(
          escola: widget.escola,
          levantamento: widget.levantamento,
          session: widget.session,
        ),
      ),
    );
    // Concluído: não há mais nada pra fazer aqui — volta pra tela da
    // escola, que mostra o histórico já com o status "Concluído".
    if (concluido == true && mounted) Navigator.of(context).pop();
  }

  // Revisão antes de concluir (2026-09-14, pedido do Barclay): antes de ir
  // pra tela de assinatura, mostra um resumo de tudo que foi cadastrado
  // neste levantamento — pra não descobrir só depois de já ter assinado
  // que esqueceu de preencher Conectividade, ou que um ambiente ficou sem
  // nenhum equipamento. Não bloqueia (o técnico pode continuar mesmo com
  // avisos), só avisa.
  Future<bool?> _confirmarRevisaoAntesDeConcluir() {
    final totalAmbientes = _ambientesCriados.length;
    final ambientesVazios = _ambientesCriados.where((a) => a.qtdEquipamentos == 0).length;
    final totalEquipamentos = _ambientesCriados.fold<int>(0, (soma, a) => soma + a.qtdEquipamentos);

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revisar antes de concluir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _linhaResumo(Icons.meeting_room_outlined, '$totalAmbientes ambiente${totalAmbientes == 1 ? '' : 's'}'),
            _linhaResumo(
              Icons.devices_other_outlined,
              '$totalEquipamentos equipamento${totalEquipamentos == 1 ? '' : 's'}',
            ),
            _linhaResumo(
              Icons.lan_outlined,
              '$_qtdConectividade link${_qtdConectividade == 1 ? '' : 's'} de conectividade',
            ),
            _linhaResumo(Icons.wifi, '$_qtdWifi rede${_qtdWifi == 1 ? '' : 's'} de wifi'),
            _linhaResumo(Icons.photo_camera_outlined, '$_qtdFotos foto${_qtdFotos == 1 ? '' : 's'}'),
            if (ambientesVazios > 0) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$ambientesVazios ambiente${ambientesVazios == 1 ? '' : 's'} sem nenhum equipamento cadastrado.',
                      style: const TextStyle(fontSize: 12, color: AppColors.warning, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Voltar')),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continuar para assinatura'),
          ),
        ],
      ),
    );
  }

  Widget _linhaResumo(IconData icone, String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icone, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 13, color: AppColors.ink))),
        ],
      ),
    );
  }

  // Ícone da AppBar com contador (bolinha com número) — mesmo padrão que já
  // existia só no de "Técnicos auxiliares", agora reaproveitado em Fotos,
  // Wifi e Conectividade também: dá pra ver de relance quantos já foram
  // cadastrados sem precisar abrir a tela.
  Widget _iconeComContador(IconData icone, int contador) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icone),
        if (contador > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(color: AppColors.warning, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
              child: Text(
                '$contador',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Só mostra o checklist inicial se a pessoa ainda não decidiu nada
    // nesta etapa (nem criou ambiente, nem pulou explicitamente) — ver
    // `_selecaoAmbientesFeita`/coluna `ambientes_selecao_feita`.
    final mostrarSelecaoInicial = !_carregando && !_selecaoAmbientesFeita && _ambientesCriados.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.escola.nome),
        actions: [
          IconButton(
            onPressed: _carregando ? null : _abrirFotos,
            icon: _iconeComContador(Icons.photo_camera_outlined, _qtdFotos),
            tooltip: 'Fotos do levantamento',
          ),
          IconButton(
            onPressed: _carregando ? null : _abrirWifi,
            icon: _iconeComContador(Icons.wifi, _qtdWifi),
            tooltip: 'Wifi da escola',
          ),
          IconButton(
            onPressed: _carregando ? null : _abrirConectividade,
            icon: _iconeComContador(Icons.lan_outlined, _qtdConectividade),
            tooltip: 'Conectividade',
          ),
          IconButton(
            onPressed: _carregando ? null : _abrirGerenciarAuxiliares,
            icon: _iconeComContador(Icons.people_outline, _auxiliares.length),
            tooltip: 'Técnicos auxiliares',
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _InfoHeader(
                  levantamento: widget.levantamento,
                  qtdAuxiliares: _auxiliares.length,
                  onTap: _abrirGerenciarAuxiliares,
                ),
                Expanded(
                  child: mostrarSelecaoInicial ? _buildSelecaoInicial() : _buildListaAmbientes(),
                ),
              ],
            ),
      bottomNavigationBar: (!_carregando && mostrarSelecaoInicial)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _salvando ? null : () => _confirmarSelecaoInicial(),
                        icon: _salvando
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_circle_outline, size: 20),
                        label: Text(_salvando ? 'Criando...' : 'Criar Ambientes (${_selecionados.length})'),
                      ),
                    ),
                    TextButton(
                      onPressed: _salvando ? null : () => _confirmarSelecaoInicial(pular: true),
                      child: const Text('Pular por enquanto — adicionar depois'),
                    ),
                  ],
                ),
              ),
            )
          : (!_carregando && !mostrarSelecaoInicial)
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _abrirConclusao,
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Concluir levantamento'),
                      ),
                    ),
                  ),
                )
              : null,
      floatingActionButton: (!_carregando && !mostrarSelecaoInicial)
          ? FloatingActionButton.extended(
              onPressed: _abrirAdicionarAmbiente,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar ambiente'),
            )
          : null,
    );
  }

  Widget _buildSelecaoInicial() {
    if (_ambientesPadrao.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Nenhum ambiente padrão sincronizado ainda. Toque em "Adicionar ambiente" depois, ou sincronize os dados na Home.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text(
            'Marque os ambientes que essa escola tem. Os obrigatórios já vêm pré-marcados — desmarque o que não existir aqui.',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
        ..._ambientesPadrao.map(
          (p) => CheckboxListTile(
            value: _selecionados.contains(p.idTipoAmbiente),
            activeColor: AppColors.primary,
            title: Text(p.nomePadrao, style: const TextStyle(fontSize: 14, color: AppColors.ink)),
            subtitle: p.obrigatorio
                ? const Text('Obrigatório', style: TextStyle(fontSize: 11, color: AppColors.warning, fontWeight: FontWeight.w700))
                : null,
            onChanged: (marcado) {
              setState(() {
                if (marcado == true) {
                  _selecionados.add(p.idTipoAmbiente);
                } else {
                  _selecionados.remove(p.idTipoAmbiente);
                }
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildListaAmbientes() {
    if (_ambientesCriados.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Nenhum ambiente ainda. Toque em "Adicionar ambiente" pra começar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
      );
    }
    final comEquipamento = _ambientesCriados.where((a) => a.qtdEquipamentos > 0).length;
    return Column(
      children: [
        _ProgressoAmbientes(total: _ambientesCriados.length, comEquipamento: comEquipamento),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemCount: _ambientesCriados.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final ambiente = _ambientesCriados[index];
              return _AmbienteCard(ambiente: ambiente, onTap: () => _abrirAmbiente(ambiente));
            },
          ),
        ),
      ],
    );
  }
}

/// Resumo fixo acima da lista de ambientes (2026-09-14, pedido do Barclay):
/// antes disso só dava pra saber "quantos ambientes faltam equipamento"
/// rolando a lista inteira e reparando nos cards em laranja. Barra +
/// contagem dão isso de relance, sem abrir nada.
class _ProgressoAmbientes extends StatelessWidget {
  const _ProgressoAmbientes({required this.total, required this.comEquipamento});
  final int total;
  final int comEquipamento;

  @override
  Widget build(BuildContext context) {
    final progresso = total == 0 ? 0.0 : comEquipamento / total;
    final completo = comEquipamento == total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$comEquipamento de $total ambiente${total == 1 ? '' : 's'} com equipamento',
                style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600),
              ),
              if (completo)
                const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.success),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progresso,
              minHeight: 6,
              backgroundColor: AppColors.line,
              color: completo ? AppColors.success : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoHeader extends StatelessWidget {
  const _InfoHeader({required this.levantamento, required this.qtdAuxiliares, required this.onTap});
  final Levantamento levantamento;
  final int qtdAuxiliares;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final temGps = levantamento.latAbertura != null && levantamento.longAbertura != null;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.primarySoft,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              const Icon(Icons.play_circle_outline, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Aberto em ${_formatarData(levantamento.dataInicio)} · ${levantamento.tecnicoAbertura}'
                  '${temGps ? '' : ' · sem GPS'}',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.people_outline, size: 14, color: qtdAuxiliares > 0 ? AppColors.primary : AppColors.muted),
              const SizedBox(width: 3),
              Text(
                qtdAuxiliares > 0 ? '$qtdAuxiliares auxiliar${qtdAuxiliares == 1 ? '' : 'es'}' : 'Adicionar auxiliar',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: qtdAuxiliares > 0 ? AppColors.primary : AppColors.muted,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  String _formatarData(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(dt.day)}/${dois(dt.month)} ${dois(dt.hour)}:${dois(dt.minute)}';
  }
}

class _AmbienteCard extends StatelessWidget {
  const _AmbienteCard({required this.ambiente, required this.onTap});
  final Ambiente ambiente;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vazio = ambiente.qtdEquipamentos == 0;
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
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                ambiente.origem == 'padrao' ? Icons.meeting_room_outlined : Icons.room_preferences_outlined,
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
                    ambiente.nomeAmbiente,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    vazio
                        ? 'Vazio — nenhum equipamento cadastrado'
                        : '${ambiente.qtdEquipamentos} equipamento${ambiente.qtdEquipamentos == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: vazio ? AppColors.warning : AppColors.muted,
                      fontWeight: vazio ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 20),
          ],
        ),
      ),
    );
  }
}
