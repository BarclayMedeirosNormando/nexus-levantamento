import 'package:uuid/uuid.dart';

import 'database.dart';

/// ATIVIDADES (2026-09-14) — log de auditoria de adição/remoção, pra o ADM
/// ver o que cada técnico fez em cada levantamento. Cobre tudo que pode ser
/// adicionado ou removido em campo: Ambiente, Equipamento, Inservível,
/// Conectividade, Wifi e Foto (ver [tipoEntidade]). Só registra criação e
/// remoção (não edição) — cada linha é um evento imutável, a tabela só
/// cresce (nunca é editada nem apagada depois de gravada).
///
/// Mesma filosofia offline-first do resto do app: `registrar()` grava local
/// na hora, sem exigir internet — quem sincroniza com o servidor é o
/// LevantamentoSyncService, do mesmo jeito que fotos_levantamento.
class AtividadeLog {
  final String id;
  final String idLevantamento;
  final String inep;
  final String matricula;
  final String? nomeTecnico;
  final String tipoEntidade;
  final String acao;
  final String? descricao;
  final String? criadoEm;

  const AtividadeLog({
    required this.id,
    required this.idLevantamento,
    required this.inep,
    required this.matricula,
    this.nomeTecnico,
    required this.tipoEntidade,
    required this.acao,
    this.descricao,
    this.criadoEm,
  });

  factory AtividadeLog.fromRow(Map<String, Object?> row) {
    return AtividadeLog(
      id: row['id'] as String,
      idLevantamento: row['id_levantamento'] as String,
      inep: row['inep'] as String,
      matricula: row['matricula'] as String,
      nomeTecnico: row['nome_tecnico'] as String?,
      tipoEntidade: row['tipo_entidade'] as String,
      acao: row['acao'] as String,
      descricao: row['descricao'] as String?,
      criadoEm: row['criado_em'] as String?,
    );
  }
}

class AtividadesRepository {
  static const _uuid = Uuid();

  /// Tipos de entidade cobertos pelo log — tudo que pode ser
  /// adicionado/removido em campo (não inclui `levantamentos`/`ambientes
  /// _padrao`/etc., que não são "criados" pelo técnico do mesmo jeito).
  static const tiposEntidade = [
    'Ambiente',
    'Equipamento',
    'Inservível',
    'Conectividade',
    'Wifi',
    'Foto',
  ];

  static const acaoAdicionado = 'Adicionado';
  static const acaoRemovido = 'Removido';

  /// Grava um evento de adição ou remoção. Chamado a partir de cada
  /// repositório (equipamentos, conectividade, wifi, fotos, ambientes) logo
  /// depois de criar/remover o registro correspondente — ver instrumentação
  /// em cada `salvar()`/`remover()`.
  Future<void> registrar({
    required String idLevantamento,
    required String inep,
    required String matricula,
    String? nomeTecnico,
    required String tipoEntidade,
    required String acao,
    String? descricao,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.insert('atividades', {
      'id': _uuid.v4(),
      'id_levantamento': idLevantamento,
      'inep': inep,
      'matricula': matricula,
      'nome_tecnico': nomeTecnico,
      'tipo_entidade': tipoEntidade,
      'acao': acao,
      'descricao': descricao,
      'criado_em': DateTime.now().toIso8601String(),
      'sync_status': 'pending',
    });
  }

  Future<List<AtividadeLog>> listarPorLevantamento(String idLevantamento) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'atividades',
      where: 'id_levantamento = ?',
      whereArgs: [idLevantamento],
      orderBy: 'criado_em DESC',
    );
    return rows.map(AtividadeLog.fromRow).toList();
  }

  /// Lista geral pra tela de auditoria (ADM) — mais recentes primeiro,
  /// com filtro opcional por técnico (matrícula) e/ou tipo de entidade.
  Future<List<AtividadeLog>> listarTudo({String? matricula, String? tipoEntidade}) async {
    final db = await AppDatabase.instance.database;
    final where = <String>[];
    final args = <Object?>[];
    if (matricula != null && matricula.isNotEmpty) {
      where.add('matricula = ?');
      args.add(matricula);
    }
    if (tipoEntidade != null && tipoEntidade.isNotEmpty) {
      where.add('tipo_entidade = ?');
      args.add(tipoEntidade);
    }
    final rows = await db.query(
      'atividades',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'criado_em DESC',
    );
    return rows.map(AtividadeLog.fromRow).toList();
  }
}
