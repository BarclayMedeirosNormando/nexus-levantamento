import 'package:uuid/uuid.dart';
import 'atividades_repository.dart';
import 'database.dart';
import 'remocoes_pendentes_repository.dart';

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
    String? nomeTecnico,
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

    // Um evento agregado só (não um por ambiente) — criados em lote na
    // seleção inicial, um por linha viraria ruído na tela de auditoria.
    await AtividadesRepository().registrar(
      idLevantamento: idLevantamento,
      inep: inep,
      matricula: matricula,
      nomeTecnico: nomeTecnico,
      tipoEntidade: 'Ambiente',
      acao: AtividadesRepository.acaoAdicionado,
      descricao: selecionados.length == 1
          ? selecionados.first.nomePadrao
          : '${selecionados.length} ambientes: ${selecionados.map((p) => p.nomePadrao).join(', ')}',
    );
  }

  /// Cria um único ambiente — usado pelo "Adicionar ambiente": tanto pra um
  /// item padrão esquecido na seleção inicial (`idTipoAmbiente` preenchido,
  /// `origem` 'padrao') quanto pra algo fora da lista, nome livre
  /// (`idTipoAmbiente` nulo, `origem` 'avulso').
  Future<void> criarUm({
    required String idLevantamento,
    required String inep,
    required String matricula,
    String? nomeTecnico,
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

    await AtividadesRepository().registrar(
      idLevantamento: idLevantamento,
      inep: inep,
      matricula: matricula,
      nomeTecnico: nomeTecnico,
      tipoEntidade: 'Ambiente',
      acao: AtividadesRepository.acaoAdicionado,
      descricao: nomeAmbiente,
    );
  }

  /// Remove um ambiente e tudo dentro dele, em cascata (2026-09-14):
  /// - EQUIPAMENTOS e EQUIPAMENTOS_INSERVIVEIS deste ambiente são apagados
  ///   de vez (não fazia sentido deixá-los "órfãos", sem ambiente nenhum);
  ///   o índice local de duplicidade (Tombamento/Série) é limpo junto, pra
  ///   não continuar bloqueando um Tombamento que na prática já foi embora.
  /// - CONECTIVIDADE ligada a este ambiente (tipo "Escola") NUNCA é
  ///   apagada — só desvinculada (ID_AMBIENTE volta a nulo): a internet em
  ///   si continua existindo na escola mesmo que o ambiente onde ela foi
  ///   registrada tenha sido removido, então apagar o link junto seria
  ///   destruir informação que não tem relação com o erro sendo corrigido.
  /// - Um único evento de auditoria é gravado (ver AtividadesRepository),
  ///   com quantos equipamentos/inserviveis foram junto — é isso que
  ///   alimenta a tela de Atividades pro ADM ver quem removeu o quê.
  ///
  /// Sincronizada de verdade (2026-09-14) — grava um tombstone em
  /// `remocoes_pendentes` pra cada linha apagada (ambiente + equipamentos +
  /// inservíveis), na MESMA transação do delete local. `LevantamentoSyncService`
  /// manda esses tombstones no próximo push e o backend (`deletarLinhasPorId`)
  /// apaga de fato as linhas na planilha — resolve o bug antigo de "remover
  /// aqui não avisava o servidor, e um pull seguinte trazia de volta".
  Future<void> removerComCascata({
    required String id,
    required String matricula,
    String? nomeTecnico,
  }) async {
    final db = await AppDatabase.instance.database;

    final ambienteRows = await db.query('ambientes', where: 'id = ?', whereArgs: [id], limit: 1);
    if (ambienteRows.isEmpty) return;
    final ambiente = ambienteRows.first;
    final idLevantamento = ambiente['id_levantamento'] as String;
    final inep = ambiente['inep'] as String;
    final nomeAmbiente = ambiente['nome_ambiente'] as String? ?? '';

    final equipamentos = await db.query('equipamentos', where: 'id_ambiente = ?', whereArgs: [id]);
    final inserviveis = await db.query('equipamentos_inserviveis', where: 'id_ambiente = ?', whereArgs: [id]);

    final agoraRemocao = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final equip in equipamentos) {
        final tombamento = equip['tombamento'] as String?;
        final numSerie = equip['num_serie'] as String?;
        if (tombamento != null && tombamento.trim().isNotEmpty) {
          await txn.delete(
            'indice_duplicidade',
            where: 'chave = ?',
            whereArgs: ['TOMBAMENTO|${tombamento.trim().toUpperCase()}'],
          );
        }
        if (numSerie != null && numSerie.trim().isNotEmpty) {
          await txn.delete(
            'indice_duplicidade',
            where: 'chave = ?',
            whereArgs: ['NUM_SERIE|${numSerie.trim().toUpperCase()}'],
          );
        }
        // Tombstone (2026-09-14) — ver RemocoesPendentesRepository: sem
        // isto, um equipamento já sincronizado voltava no próximo pull
        // mesmo tendo sido apagado aqui junto com o ambiente.
        await txn.insert('remocoes_pendentes', {
          'id': _uuid.v4(),
          'tabela': 'equipamentos',
          'id_registro': equip['id'] as String,
          'id_levantamento': idLevantamento,
          'criado_em': agoraRemocao,
        });
      }
      for (final inservivel in inserviveis) {
        await txn.insert('remocoes_pendentes', {
          'id': _uuid.v4(),
          'tabela': 'equipamentos_inserviveis',
          'id_registro': inservivel['id'] as String,
          'id_levantamento': idLevantamento,
          'criado_em': agoraRemocao,
        });
      }
      await txn.delete('equipamentos', where: 'id_ambiente = ?', whereArgs: [id]);
      await txn.delete('equipamentos_inserviveis', where: 'id_ambiente = ?', whereArgs: [id]);
      await txn.update(
        'conectividade',
        {
          'id_ambiente': null,
          'atualizado_em': DateTime.now().toIso8601String(),
          'sync_status': 'pending',
        },
        where: 'id_ambiente = ?',
        whereArgs: [id],
      );
      await txn.delete('ambientes', where: 'id = ?', whereArgs: [id]);
      // Tombstone do próprio ambiente — ver comentário acima.
      await txn.insert('remocoes_pendentes', {
        'id': _uuid.v4(),
        'tabela': 'ambientes',
        'id_registro': id,
        'id_levantamento': idLevantamento,
        'criado_em': agoraRemocao,
      });
    });

    final partes = <String>[nomeAmbiente];
    if (equipamentos.isNotEmpty) partes.add('${equipamentos.length} equipamento(s)');
    if (inserviveis.isNotEmpty) partes.add('${inserviveis.length} inservível(is)');
    await AtividadesRepository().registrar(
      idLevantamento: idLevantamento,
      inep: inep,
      matricula: matricula,
      nomeTecnico: nomeTecnico,
      tipoEntidade: 'Ambiente',
      acao: AtividadesRepository.acaoRemovido,
      descricao: partes.join(' — '),
    );
  }

  /// Renomeia um ambiente já criado — pedido do usuário: ambientes criados
  /// (inclusive nome errado/apelido provisório digitado em campo) ainda não
  /// tinham como ser corrigidos depois, só recriados do zero.
  Future<void> renomear({required String id, required String novoNome}) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'ambientes',
      {
        'nome_ambiente': novoNome,
        'atualizado_em': DateTime.now().toIso8601String(),
        // Mesma lógica de guarda de WifiRepository.atualizar /
        // ConectividadeRepository.atualizarLinkEscola: sem isso, um
        // ambiente renomeado depois de já sincronizado nunca voltava a
        // fila de push, e o próximo pull trazia o nome antigo de volta.
        'sync_status': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
