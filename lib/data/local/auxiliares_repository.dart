import 'package:sqflite/sqflite.dart';
import 'database.dart';

class TecnicoOpcao {
  final String matricula;
  final String nome;
  const TecnicoOpcao({required this.matricula, required this.nome});
}

/// LEVANTAMENTO_TECNICOS (§2/§5 Tela 3/§5b do spec) — quem, além de quem
/// abriu, enxerga e edita um levantamento. Usado tanto na seleção inicial
/// (abertura do levantamento) quanto pra adicionar/remover depois. As
/// regras de visibilidade que essa tabela alimenta ficam em
/// `LevantamentosRepository`, não aqui — este arquivo só gerencia quem está
/// na lista de auxiliares de cada levantamento.
class AuxiliaresRepository {
  /// Técnicos com login habilitado no app — candidatos a auxiliar. Exclui
  /// quem já é o dono do levantamento (`excluirMatricula`, obrigatório —
  /// não faz sentido a pessoa se adicionar como "auxiliar" de si mesma) e,
  /// opcionalmente, quem já está na lista de auxiliares atuais.
  Future<List<TecnicoOpcao>> listarTecnicosDisponiveis({
    required String excluirMatricula,
    Set<String> excluirTambem = const {},
  }) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'servidores',
      where: 'login_habilitado = 1 AND matricula != ?',
      whereArgs: [excluirMatricula],
      orderBy: 'nome ASC',
    );
    return rows
        .map((r) => TecnicoOpcao(
              matricula: r['matricula'] as String,
              nome: (r['nome'] as String?)?.trim().isNotEmpty == true ? r['nome'] as String : r['matricula'] as String,
            ))
        .where((t) => !excluirTambem.contains(t.matricula))
        .toList();
  }

  /// Auxiliares já adicionados a um levantamento, com nome (join com
  /// SERVIDORES) — se o técnico ainda não sincronizou essa matrícula
  /// localmente, cai no fallback de mostrar a própria matrícula como nome.
  Future<List<TecnicoOpcao>> listarAuxiliares(String idLevantamento) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT lt.matricula_tecnico AS matricula, s.nome AS nome
      FROM levantamento_tecnicos lt
      LEFT JOIN servidores s ON s.matricula = lt.matricula_tecnico
      WHERE lt.id_levantamento = ?
      ORDER BY s.nome ASC
    ''', [idLevantamento]);
    return rows
        .map((r) => TecnicoOpcao(
              matricula: r['matricula'] as String,
              nome: (r['nome'] as String?)?.trim().isNotEmpty == true ? r['nome'] as String : r['matricula'] as String,
            ))
        .toList();
  }

  /// Adiciona vários de uma vez (usado na seleção inicial, na abertura do
  /// levantamento) — `ConflictAlgorithm.ignore` porque a chave primária é
  /// composta (id_levantamento, matricula_tecnico); reenviar a mesma
  /// matrícula não deve dar erro, só não duplica.
  Future<void> adicionarEmLote({required String idLevantamento, required List<String> matriculas}) async {
    if (matriculas.isEmpty) return;
    final db = await AppDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final matricula in matriculas) {
      batch.insert(
        'levantamento_tecnicos',
        {
          'id_levantamento': idLevantamento,
          'matricula_tecnico': matricula,
          'adicionado_em': agora,
          'sync_status': 'pending',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> adicionar({required String idLevantamento, required String matricula}) {
    return adicionarEmLote(idLevantamento: idLevantamento, matriculas: [matricula]);
  }

  /// Remove vários de uma vez (usado na tela de gerenciamento, que agora
  /// deixa marcar/desmarcar vários técnicos e confirmar tudo junto, em vez
  /// de remover um por um a cada toque).
  Future<void> removerEmLote({required String idLevantamento, required List<String> matriculas}) async {
    if (matriculas.isEmpty) return;
    final db = await AppDatabase.instance.database;
    final batch = db.batch();
    for (final matricula in matriculas) {
      batch.delete(
        'levantamento_tecnicos',
        where: 'id_levantamento = ? AND matricula_tecnico = ?',
        whereArgs: [idLevantamento, matricula],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> remover({required String idLevantamento, required String matricula}) {
    return removerEmLote(idLevantamento: idLevantamento, matriculas: [matricula]);
  }
}
