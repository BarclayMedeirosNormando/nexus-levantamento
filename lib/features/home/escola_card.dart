import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/escolas_repository.dart';

/// Card de escola — compartilhado entre a Home (lista de busca) e a tela de
/// Escolas dentro de um Município (navegação em árvore).
class EscolaCard extends StatelessWidget {
  const EscolaCard({super.key, required this.escola, required this.onTap});
  final Escola escola;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.school_outlined, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Hero(
                      tag: 'escola-nome-${escola.inep}',
                      child: Material(
                        type: MaterialType.transparency,
                        child: Text(
                          escola.nome,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (escola.municipio != null && escola.municipio!.isNotEmpty) escola.municipio!,
                        'INEP ${escola.inep}',
                      ].join(' · '),
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
