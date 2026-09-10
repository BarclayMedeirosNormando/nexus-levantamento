import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/escolas_repository.dart';
import '../../data/remote/auth_service.dart';
import 'escolas_lista_screen.dart';
import 'tree_tile.dart';

/// Nível 2 da árvore: municípios dentro de uma Regional.
class MunicipiosScreen extends StatefulWidget {
  const MunicipiosScreen({super.key, required this.regional, required this.session});
  final String regional;
  final Session session;

  @override
  State<MunicipiosScreen> createState() => _MunicipiosScreenState();
}

class _MunicipiosScreenState extends State<MunicipiosScreen> {
  final _repo = EscolasRepository();
  late Future<List<MunicipioResumo>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.listarMunicipios(widget.regional);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.regional)),
      body: FutureBuilder<List<MunicipioResumo>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final municipios = snapshot.data!;
          if (municipios.isEmpty) {
            return const Center(
              child: Text('Nenhum município encontrado.', style: TextStyle(color: AppColors.muted)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            itemCount: municipios.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final m = municipios[index];
              return TreeTile(
                icon: Icons.location_city_outlined,
                titulo: m.municipio,
                subtitulo: '${m.totalEscolas} escola${m.totalEscolas == 1 ? '' : 's'}',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EscolasListaScreen(
                        regional: widget.regional,
                        municipio: m.municipio,
                        session: widget.session,
                      ),
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
