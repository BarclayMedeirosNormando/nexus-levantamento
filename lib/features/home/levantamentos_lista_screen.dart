import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/levantamentos_repository.dart';
import '../../data/remote/auth_service.dart';
import '../levantamento/levantamento_screen.dart';

/// Lista cheia de levantamentos por status (2026-09-12) — aberta pelos
/// cartões-resumo "Em andamento"/"Concluídos" da Home (ver
/// `home_screen.dart`), pra não precisar espremer tudo inline na tela
/// principal (que só mostrava "em andamento", sem nunca ter tido uma visão
/// de concluídos). Cada item abre o mesmo `LevantamentoScreen` de sempre —
/// não existe uma tela de "visualização" separada; concluído reaberto pelo
/// próprio ADM (ver ConclusaoScreen/backend `reabrir_levantamento`) volta a
/// aparecer normalmente em "Em andamento" no próximo carregamento da Home.
class LevantamentosListaScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$titulo (${itens.length})')),
      body: itens.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nada por aqui.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ),
            )
          : FadeIn(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                itemCount: itens.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _ItemCard(item: itens[index], session: session),
              ),
            ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.session});
  final LevantamentoComEscola item;
  final Session session;

  @override
  Widget build(BuildContext context) {
    final concluido = item.levantamento.status == 'concluido';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LevantamentoScreen(
              escola: item.escola,
              levantamento: item.levantamento,
              session: session,
            ),
          ),
        );
      },
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
                    item.escola.nome,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.escola.municipio != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.escola.municipio!,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ),
                  if (session.isAdm && item.levantamento.tecnicoAbertura.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Técnico: ${item.levantamento.tecnicoAbertura}',
                        style: const TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
