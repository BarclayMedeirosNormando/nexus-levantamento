import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/catalogo_repository.dart';
import '../../data/remote/auth_service.dart';
import 'modelo_form_screen.dart';

/// Tela "Catálogo de Modelos" — pedido do usuário: em vez de só deixar o
/// catálogo crescer sozinho a partir dos equipamentos cadastrados em campo
/// (processarCatalogo() no backend), dá pra pré-cadastrar Tipo/Marca/Modelo
/// aqui, com internet, antes de ir a campo — daí, dentro do ambiente, o
/// fluxo de "Novo equipamento" já busca nesse catálogo primeiro (ver
/// showCatalogoPickerSheet em ambiente_detail_screen.dart), e só cai pro
/// formulário em branco se a pessoa escolher "Digitar sem catálogo".
///
/// Criar/editar um modelo aqui é uma chamada online
/// (CatalogoRepository.criarModelo/atualizarModelo — ações
/// `criar_modelo_catalogo`/`atualizar_modelo_catalogo` no backend), pra
/// sincronizar de verdade entre aparelhos assim que salvo, não só quando o
/// primeiro equipamento que usa esse modelo for sincronizado depois.
class CatalogoModelosScreen extends StatefulWidget {
  const CatalogoModelosScreen({super.key, required this.session});
  final Session session;

  @override
  State<CatalogoModelosScreen> createState() => _CatalogoModelosScreenState();
}

class _CatalogoModelosScreenState extends State<CatalogoModelosScreen> {
  final _repo = CatalogoRepository();
  final _buscaController = TextEditingController();
  List<CatalogoItem> _itens = const [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _buscaController.addListener(_onBuscaChanged);
    _buscar('');
  }

  @override
  void dispose() {
    _buscaController.removeListener(_onBuscaChanged);
    _buscaController.dispose();
    super.dispose();
  }

  void _onBuscaChanged() => _buscar(_buscaController.text);

  Future<void> _buscar(String termo) async {
    setState(() => _carregando = true);
    final itens = await _repo.buscar(termo);
    if (!mounted) return;
    // Evita corrida entre buscas digitadas rápido.
    if (_buscaController.text != termo) return;
    setState(() {
      _itens = itens;
      _carregando = false;
    });
  }

  Future<void> _abrirNovoModelo() async {
    final resultado = await Navigator.of(context).push<ModeloFormResultado>(
      MaterialPageRoute(builder: (_) => ModeloFormScreen(session: widget.session)),
    );
    if (resultado == null || !mounted) return;
    AppSnackbar.sucesso(context, 'Modelo "${resultado.item.label}" disponível no catálogo.');
    await _buscar(_buscaController.text);
  }

  Future<void> _abrirEditarModelo(CatalogoItem item) async {
    final resultado = await Navigator.of(context).push<ModeloFormResultado>(
      MaterialPageRoute(builder: (_) => ModeloFormScreen(session: widget.session, existente: item)),
    );
    if (resultado == null || !mounted) return;

    // Atualização otimista: troca o item na lista JÁ EM MEMÓRIA com o que
    // acabou de voltar do formulário, antes mesmo de reconsultar o banco
    // local. Sem isso, a tela dependia 100% de _buscar() reler
    // catalogo_equipamentos a tempo — se esse read ficar atrás da escrita
    // por qualquer motivo (ou se a tela estiver rodando uma versão em
    // hot-reload defasada da lógica de busca), o cartão continua mostrando
    // o valor antigo mesmo com o servidor e o banco local já certos.
    setState(() {
      _itens = [
        for (final atual in _itens)
          if (atual.idCatalogo == resultado.item.idCatalogo) resultado.item else atual,
      ];
    });

    final n = resultado.equipamentosAtualizados ?? 0;
    final complemento = n > 0
        ? ' $n equipamento${n == 1 ? '' : 's'} já cadastrado${n == 1 ? '' : 's'} atualizado${n == 1 ? '' : 's'} junto.'
        : '';
    AppSnackbar.sucesso(context, 'Modelo "${resultado.item.label}" atualizado.$complemento');
    await _buscar(_buscaController.text);
  }

  @override
  Widget build(BuildContext context) {
    final buscando = _buscaController.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo de Modelos')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _buscaController,
              decoration: InputDecoration(
                hintText: 'Buscar por tipo, marca ou modelo',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: AppColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Pré-cadastre modelos aqui pra reaproveitar depois, direto no ambiente. Toque num modelo pra editar.',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _itens.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            buscando
                                ? 'Nenhum modelo encontrado pra "${_buscaController.text}".'
                                : 'Nenhum modelo no catálogo ainda. Toque em "Novo modelo" pra cadastrar o primeiro.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.muted, fontSize: 13),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        itemCount: _itens.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _itens[index];
                          return _ModeloCard(
                            item: item,
                            onTap: () => _abrirEditarModelo(item),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirNovoModelo,
        icon: const Icon(Icons.add),
        label: const Text('Novo modelo'),
      ),
    );
  }
}

class _ModeloCard extends StatelessWidget {
  const _ModeloCard({required this.item, required this.onTap});
  final CatalogoItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitulo = [
      if (item.marca != null && item.marca!.isNotEmpty) item.marca,
      if (item.modelo != null && item.modelo!.isNotEmpty) item.modelo,
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
              child: const Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.tipoEquipamento,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink),
                  ),
                  if (subtitulo.isNotEmpty)
                    Text(subtitulo, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
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
