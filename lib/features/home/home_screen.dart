import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/escolas_repository.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/auth_service.dart';
import '../../data/sync_service.dart';
import '../auth/login_screen.dart';
import '../escola/escola_detail_screen.dart';
import 'escola_card.dart';
import 'regionais_screen.dart';

/// "Minhas Escolas". Dois modos, decididos pelo campo de busca:
/// - **Busca vazia**: navegação em árvore Regional → Município → Escolas
///   (`RegionaisLista`, embutida) — mais fácil de navegar em 647 escolas do
///   que rolar uma lista só.
/// - **Busca preenchida**: lista plana filtrada por nome/INEP/município,
///   ignorando a árvore (a pessoa já sabe o que procura).
///
/// ESCOLAS é tabela de referência, só leitura no app (ver §4/§9 do spec) —
/// tudo aqui lê do SQLite local, sync é só o botão/ícone pra atualizar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});
  final Session session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _syncService = SyncService();
  final _escolasRepo = EscolasRepository();
  final _buscaController = TextEditingController();

  bool _syncing = false;
  bool _carregandoBusca = false;
  String? _erroSync;
  List<Escola> _resultadosBusca = const [];

  // Muda a cada sync bem-sucedido, pra forçar a árvore de regionais (que
  // carrega uma vez no initState dela) a recarregar com dados novos.
  Key _arvoreKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _buscaController.addListener(_onBuscaChanged);
  }

  @override
  void dispose() {
    _buscaController.removeListener(_onBuscaChanged);
    _buscaController.dispose();
    super.dispose();
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

  Future<void> _sincronizar() async {
    setState(() {
      _syncing = true;
      _erroSync = null;
    });
    try {
      await _syncService.pullReferencia(widget.session);
      if (!mounted) return;
      setState(() => _arvoreKey = UniqueKey());
      if (_buscaController.text.trim().isNotEmpty) {
        await _buscarEscolas(_buscaController.text);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _erroSync = e.message);
    } catch (e) {
      // Qualquer erro fora do ApiException (ex: gravação local) também
      // precisa aparecer — nunca falhar silenciosamente (ver §14 do spec).
      // ignore: avoid_print
      print('Erro inesperado ao sincronizar: $e');
      if (!mounted) return;
      setState(() => _erroSync = 'Erro inesperado: $e');
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
          IconButton(onPressed: _sair, icon: const Icon(Icons.logout), tooltip: 'Sair'),
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
    return ListView.separated(
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
    );
  }
}
