import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/escolas_repository.dart';
import '../../data/remote/auth_service.dart';
import '../escola/escola_detail_screen.dart';
import 'escola_card.dart';

/// Nível 3 (folha) da árvore: escolas dentro de um Município específico de
/// uma Regional.
class EscolasListaScreen extends StatefulWidget {
  const EscolasListaScreen({
    super.key,
    required this.regional,
    required this.municipio,
    required this.session,
  });
  final String regional;
  final String municipio;
  final Session session;

  @override
  State<EscolasListaScreen> createState() => _EscolasListaScreenState();
}

class _EscolasListaScreenState extends State<EscolasListaScreen> {
  final _repo = EscolasRepository();
  late Future<List<Escola>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.listarPorRegionalMunicipio(widget.regional, widget.municipio);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.municipio)),
      body: FutureBuilder<List<Escola>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final escolas = snapshot.data!;
          if (escolas.isEmpty) {
            return const Center(
              child: Text('Nenhuma escola encontrada.', style: TextStyle(color: AppColors.muted)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            itemCount: escolas.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final escola = escolas[index];
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
        },
      ),
    );
  }
}
