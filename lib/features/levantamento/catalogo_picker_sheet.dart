import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/catalogo_repository.dart';
import '../../data/remote/auth_service.dart';
import '../catalogo/modelo_form_screen.dart';

/// Resultado de [showCatalogoPickerSheet]: ou a pessoa escolheu um item do
/// catálogo ([CatalogoPickerResult.selecionado]), ou preferiu não usar o
/// catálogo e digitar na mão ([CatalogoPickerResult.manual] — o formulário
/// de Equipamento simplesmente fica em branco, igual já era o comportamento
/// antes desta feature). `null` (sheet fechado sem escolher nada, ex: botão
/// voltar do Android) significa "cancelou a criação do equipamento".
class CatalogoPickerResult {
  final CatalogoItem? item;
  const CatalogoPickerResult._(this.item);

  factory CatalogoPickerResult.selecionado(CatalogoItem item) => CatalogoPickerResult._(item);
  factory CatalogoPickerResult.manual() => const CatalogoPickerResult._(null);
}

/// Bottom sheet compartilhado de busca no catálogo. Usado em dois lugares:
/// pelo ícone de lupa dentro do formulário de Equipamento (Tela 6), e pelo
/// próprio botão "Novo equipamento" em AmbienteDetailScreen — esse segundo
/// caso é o fluxo "catálogo primeiro" pedido: ao incluir um equipamento num
/// ambiente, busca nessa área antes de abrir o formulário; se o modelo não
/// existir ainda, "Criar modelo" cadastra ali mesmo, sem sair do fluxo.
Future<CatalogoPickerResult?> showCatalogoPickerSheet({
  required BuildContext context,
  required Session session,
}) {
  return showModalBottomSheet<CatalogoPickerResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _CatalogoPickerSheet(session: session),
  );
}

class _CatalogoPickerSheet extends StatefulWidget {
  const _CatalogoPickerSheet({required this.session});
  final Session session;

  @override
  State<_CatalogoPickerSheet> createState() => _CatalogoPickerSheetState();
}

class _CatalogoPickerSheetState extends State<_CatalogoPickerSheet> {
  final _repo = CatalogoRepository();
  final _queryController = TextEditingController();
  List<CatalogoItem> _resultados = const [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _buscar('');
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _buscar(String query) async {
    setState(() => _carregando = true);
    final resultados = await _repo.buscar(query);
    if (!mounted) return;
    setState(() {
      _resultados = resultados;
      _carregando = false;
    });
  }

  Future<void> _abrirCriarModelo() async {
    // Tela cheia, não diálogo (ver comentário em ModeloFormScreen — um
    // AlertDialog aqui travava o app no Windows). Empurra por cima do
    // bottom sheet, que continua aberto por baixo; ao voltar com um item
    // criado, fecha o sheet inteiro já com o resultado.
    final resultado = await Navigator.of(context).push<ModeloFormResultado>(
      MaterialPageRoute(
        builder: (_) => ModeloFormScreen(session: widget.session, tipoInicial: _queryController.text),
      ),
    );
    if (resultado == null || !mounted) return;
    Navigator.of(context).pop(CatalogoPickerResult.selecionado(resultado.item));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Buscar no catálogo',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink),
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _queryController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Tipo, marca ou modelo...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _buscar,
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(CatalogoPickerResult.manual()),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Digitar sem catálogo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _abrirCriarModelo,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Criar modelo'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _carregando
                    ? const Center(child: CircularProgressIndicator())
                    : _resultados.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Nada encontrado no catálogo pra esse termo. Toque em "Criar modelo" pra cadastrar um novo.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.muted, fontSize: 13),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            itemCount: _resultados.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = _resultados[index];
                              return ListTile(
                                title: Text(item.label),
                                onTap: () => Navigator.of(context).pop(CatalogoPickerResult.selecionado(item)),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
