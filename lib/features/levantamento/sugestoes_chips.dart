import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Fileira horizontal de chips de sugestão — usada nos campos de Tipo e
/// Marca do formulário de Equipamento/Inservível (Tela 6/5). Em vez de um
/// Autocomplete "de verdade" (que depende de uma API mais recente do
/// Flutter e é mais frágil de acertar sem rodar o app na hora), isso é só
/// um atalho visual: tocar num chip preenche o campo, mas o campo continua
/// sempre um TextField comum — digitar livre nunca é bloqueado.
class SugestoesChips extends StatelessWidget {
  const SugestoesChips({
    super.key,
    required this.opcoes,
    required this.controller,
    required this.onSelecionado,
  });

  final List<String> opcoes;
  final TextEditingController controller;
  final VoidCallback onSelecionado;

  @override
  Widget build(BuildContext context) {
    if (opcoes.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: opcoes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final opcao = opcoes[index];
          final selecionado = controller.text.trim().toLowerCase() == opcao.toLowerCase();
          return ChoiceChip(
            label: Text(opcao, style: const TextStyle(fontSize: 12)),
            selected: selecionado,
            selectedColor: AppColors.primarySoft,
            labelStyle: TextStyle(color: selecionado ? AppColors.primary : AppColors.ink),
            onSelected: (_) {
              controller.text = opcao;
              onSelecionado();
            },
          );
        },
      ),
    );
  }
}
