import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/escolas_repository.dart';
import '../../data/remote/auth_service.dart';
import 'municipios_screen.dart';
import 'tree_tile.dart';

/// Nível 1 da navegação em árvore: Regional → Município → Escolas (a pedido
/// do usuário, mais fácil de navegar em 647 escolas do que uma lista só).
///
/// Fica como uma tela própria (pra ter sua própria AppBar/voltar), mas a
/// Home também mostra esse mesmo conteúdo embutido quando a busca está
/// vazia — ver `RegionaisLista` abaixo, reaproveitada nos dois lugares.
class RegionaisScreen extends StatelessWidget {
  const RegionaisScreen({super.key, required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Regionais')),
      body: RegionaisLista(session: session),
    );
  }
}

/// Conteúdo em si (sem Scaffold/AppBar), pra poder ser embutido direto na
/// Home também, sem duplicar a lógica de carregar/exibir regionais.
class RegionaisLista extends StatefulWidget {
  const RegionaisLista({super.key, required this.session});
  final Session session;

  @override
  State<RegionaisLista> createState() => _RegionaisListaState();
}

class _RegionaisListaState extends State<RegionaisLista> {
  final _repo = EscolasRepository();
  late Future<List<RegionalResumo>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.listarRegionais();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RegionalResumo>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final regionais = snapshot.data!;
        if (regionais.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('Nenhuma escola sincronizada ainda.', style: TextStyle(color: AppColors.muted)),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          itemCount: regionais.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final r = regionais[index];
            return TreeTile(
              icon: Icons.map_outlined,
              titulo: r.regional,
              subtitulo: '${r.totalEscolas} escola${r.totalEscolas == 1 ? '' : 's'}',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MunicipiosScreen(regional: r.regional, session: widget.session),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
