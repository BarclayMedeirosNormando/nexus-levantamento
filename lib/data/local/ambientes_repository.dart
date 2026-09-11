import 'package:uuid/uuid.dart';
import 'database.dart';

class AmbientePadrao {
  final String idTipoAmbiente;
  final String nomePadrao;
  final bool obrigatorio;

  const AmbientePadrao({
    required this.idTipoAmbiente,
    required this.nomePadrao,
    required this.obrigatorio,
  });

  factory AmbientePadrao.fromRow(Map<String, Object?> row) {
    return AmbientePadrao(
      idTipoAmbiente: row['id_tipo_ambiente'] as String,
      nomePadrao: row['nome_padrao'] as String? ?? '',
      obrigatorio: (row['obrigatorio'] as int? ?? 0) == 1,
    );
  }
}

class Ambiente {
  final String id;
  final String idLevantamento;
  final String? idTipoAmbiente;
  final String nomeAmbiente;
  final String origem; // 'padrao' | 'avulso'
  final int qtdEquipamentos;

  const Ambiente({
    required this.id,
    required this.idLevantamento,
    this.idTipoAmbiente,
    required this.nomeAmbiente,
    required this.origem,
    required this.qtdEquipamentos,
  });
}

/// AMBIENTES (§4/§5 Tela 4 do spec) — criados em lote a partir de
/// AMBIENTES_PADRAO na abertura do levantamento (checklist com os
/// `OBRIGATORIO=true` pré-marcados), ou um de cada vez depois via
/// "Adicionar ambiente" (item padrão restante ou nome livre/avulso).
class AmbientesRepository {
  static const _uuid = Uuid();

  Future<List<AmbientePadrao>> listarPadrao() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('ambientes_padrao', orderBy: 'obrigatorio DESC, nome_padrao ASC');
    return rows.map(AmbientePadrao.fromRow).toList();
  }

  /// Ambientes já criados para este levantamento, com contagem de
  /// equipamentos via subquery — Tela 5 (cadastro de equipamento) ainda não
  /// existe, mas a contagem já fica certa pra quando existir.
  Future<List<Ambiente>> listarPorLevantamento(String idLevantamento) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT a.id, a.id_levantamento, a.id_tipo_ambiente, a.nome_ambiente, a.origem,
             (SELECT COUNT(*) FROM equipamentos e WHERE e.id_ambiente = a.id) AS qtd_equipamentos
      FROM ambientes a
      WHERE a.id_levantamento = ?
      ORDER BY a.criado_em ASC
    ''', [idLevantamento]);
    return rows
        .map((row) => Ambiente(
              id: row['id'] as String,
              idLevantamento: row['id_levantamento'] as String,
              idTipoAmbiente: row['id_tipo_ambiente'] as String?,
              nomeAmbiente: row['nome_ambiente'] as String? ?? '',
              origem: row['origem'] as String? ?? 'avulso',
              qtdEquipamentos: (row['qtd_equipamentos'] as int?) ?? 0,
            ))
        .toList();
  }

  /// Cria vários AMBIENTES de uma vez, a partir de itens de AMBIENTES_PADRAO
  /// selecionados na tela de seleção inicial — sempre em lote (`Batch`),
  /// nunca um insert por vez, pra não fazer N idas ao SQLite ao confirmar.
  Future<void> criarEmLote({
    required String idLevantamento,
    required String inep,
    required String matricula,
    required List<AmbientePadrao> selecionados,
  }) async {
    if (selecionados.isEmpty) return;
    final db = await AppDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final padrao in selecionados) {
      batch.insert('ambientes', {
        'id': _uuid.v4(),
        'id_levantamento': idLevantamento,
        'inep': inep,
        'id_tipo_ambiente': padrao.idTipoAmbiente,
        'nome_ambiente': padrao.nomePadrao,
        'origem': 'padrao',
        'criado_por': matricula,
        'criado_em': agora,
        'atualizado_em': agora,
        'sync_status': 'pending',
      });
    }
    await batch.commit(noResult: true);
  }

  /// Cria um único ambiente — usado pelo "Adicionar ambiente": tanto pra um
  /// item padrão esquecido na seleção inicial (`idTipoAmbiente` preenchido,
  /// `origem` 'padrao') quanto pra algo fora da lista, nome livre
  /// (`idTipoAmbiente` nulo, `origem` 'avulso').
  Future<void> criarUm({
    required String idLevantamento,
    required String inep,
    required String matricula,
    String? idTipoAmbiente,
    required String nomeAmbiente,
    required String origem,
  }) async {
    final db = await AppDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();
    await db.insert('ambientes', {
      'id': _uuid.v4(),
      'id_levantamento': idLevantamento,
      'inep': inep,
      'id_tipo_ambiente': idTipoAmbiente,
      'nome_ambiente': nomeAmbiente,
      'origem': origem,
      'criado_por': matricula,
      'criado_em': agora,
      'atualizado_em': agora,
      'sync_status': 'pending',
    });
  }

  /// Renomeia um ambiente já criado — pedido do usuário: ambientes criados
  /// (inclusive nome errado/apelido provisório digitado em campo) ainda não
  /// tinham como ser corrigidos depois, só recriados do zero.
  Future<void> renomear({required String id, required String novoNome}) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'ambientes',
      {'nome_ambiente': novoNome, 'atualizado_em': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
