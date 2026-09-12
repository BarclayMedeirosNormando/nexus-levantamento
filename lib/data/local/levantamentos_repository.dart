import 'package:uuid/uuid.dart';
import 'database.dart';
import 'escolas_repository.dart';

class Levantamento {
  final String id;
  final String inep;
  final String tecnicoAbertura;
  final String? dataInicio;
  final double? latAbertura;
  final double? longAbertura;
  final String status; // 'em_andamento' | 'concluido'
  final bool ambientesSelecaoFeita;

  const Levantamento({
    required this.id,
    required this.inep,
    required this.tecnicoAbertura,
    this.dataInicio,
    this.latAbertura,
    this.longAbertura,
    required this.status,
    this.ambientesSelecaoFeita = false,
  });

  factory Levantamento.fromRow(Map<String, Object?> row) {
    return Levantamento(
      id: row['id'] as String,
      inep: row['inep'] as String,
      tecnicoAbertura: row['tecnico_abertura'] as String? ?? '',
      dataInicio: row['data_inicio'] as String?,
      latAbertura: (row['lat_abertura'] as num?)?.toDouble(),
      longAbertura: (row['long_abertura'] as num?)?.toDouble(),
      status: row['status'] as String? ?? 'em_andamento',
      ambientesSelecaoFeita: (row['ambientes_selecao_feita'] as int? ?? 0) == 1,
    );
  }
}

/// Levantamento em_andamento + a escola dele já junta — usado na Home (§5
/// Tela 2) pra mostrar "o que ficou pra trás" sem precisar navegar pela
/// árvore de novo.
class LevantamentoComEscola {
  final Levantamento levantamento;
  final Escola escola;
  const LevantamentoComEscola({required this.levantamento, required this.escola});
}

// Subconsulta reaproveitada nos três métodos de visibilidade abaixo: um
// levantamento é "meu" (pra quem não é ADM) se eu abri ele OU se eu fui
// adicionado como auxiliar (LEVANTAMENTO_TECNICOS, §2/§5b do spec).
const _condicaoDonoOuAuxiliar = '''(
  tecnico_abertura = ?
  OR id IN (SELECT id_levantamento FROM levantamento_tecnicos WHERE matricula_tecnico = ?)
)''';

/// LEVANTAMENTOS é transacional (ver §4/§6 do spec) — criado/editado em
/// campo, marcado `sync_status='pending'` até o `push_levantamento` (que
/// ainda não existe no app; por enquanto o registro fica só local). UUID
/// gerado no cliente (`uuid` pkg) — mesma ideia do UNIQUEID() do AppSheet,
/// garante idempotência quando o sync entrar.
///
/// Regra de visibilidade (§2 "Auxiliares e visibilidade", confirmada pelo
/// usuário): ADM enxerga tudo, sempre — em_andamento ou concluído. Técnico
/// comum só enxerga um levantamento enquanto ele está em_andamento E o
/// técnico é o dono ou um auxiliar; assim que o levantamento é concluído,
/// ele some da visão desse técnico — só volta a aparecer se for reaberto
/// (status volta pra em_andamento). Essa regra é aplicada em todo método de
/// leitura abaixo que recebe `matricula`/`isAdm`.
class LevantamentosRepository {
  static const _uuid = Uuid();

  /// Levantamento em_andamento visível pro usuário nesta escola (dono,
  /// auxiliar, ou qualquer um se for ADM) — usado em EscolaDetailScreen pra
  /// decidir entre "Novo levantamento" e "Continuar levantamento em
  /// andamento".
  Future<Levantamento?> buscarEmAndamento({
    required String inep,
    required String matricula,
    required bool isAdm,
  }) async {
    final db = await AppDatabase.instance.database;
    final where = isAdm ? 'inep = ? AND status = ?' : 'inep = ? AND status = ? AND $_condicaoDonoOuAuxiliar';
    final whereArgs = isAdm ? [inep, 'em_andamento'] : [inep, 'em_andamento', matricula, matricula];
    final rows = await db.query(
      'levantamentos',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'criado_em DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Levantamento.fromRow(rows.first);
  }

  /// Histórico de levantamentos da escola, já filtrado pela regra de
  /// visibilidade acima: ADM vê tudo (inclusive concluídos); técnico só vê
  /// os em_andamento dos quais é dono ou auxiliar — concluído some da
  /// lista dele até (se) ser reaberto.
  Future<List<Levantamento>> listarHistorico({
    required String inep,
    required String matricula,
    required bool isAdm,
  }) async {
    final db = await AppDatabase.instance.database;
    if (isAdm) {
      final rows = await db.query('levantamentos', where: 'inep = ?', whereArgs: [inep], orderBy: 'criado_em DESC');
      return rows.map(Levantamento.fromRow).toList();
    }
    final rows = await db.query(
      'levantamentos',
      where: "inep = ? AND status = 'em_andamento' AND $_condicaoDonoOuAuxiliar",
      whereArgs: [inep, matricula, matricula],
      orderBy: 'criado_em DESC',
    );
    return rows.map(Levantamento.fromRow).toList();
  }

  /// Todos os levantamentos em_andamento visíveis pro usuário logado — ADM
  /// vê todos (§2 "Papéis de usuário"), técnico comum só vê os que ele
  /// mesmo abriu ou onde é auxiliar. Junta com ESCOLAS pra já trazer
  /// nome/município pra exibir direto na Home, sem N+1 de leitura.
  Future<List<LevantamentoComEscola>> listarEmAndamento({
    required String matricula,
    required bool isAdm,
  }) async {
    final db = await AppDatabase.instance.database;
    // Nota: `tecnico_abertura` e `id` (dentro de `_condicaoDonoOuAuxiliar`)
    // só existem na tabela `levantamentos` — mesmo sem prefixo `l.`, o
    // SQLite resolve sem ambiguidade dentro do JOIN com `escolas`.
    final where = isAdm ? "l.status = 'em_andamento'" : "l.status = 'em_andamento' AND $_condicaoDonoOuAuxiliar";
    final whereArgs = isAdm ? const [] : [matricula, matricula];
    final rows = await db.rawQuery('''
      SELECT
        l.id, l.inep, l.tecnico_abertura, l.data_inicio, l.lat_abertura, l.long_abertura, l.status,
        e.inep AS e_inep, e.nome AS e_nome, e.municipio AS e_municipio, e.regional AS e_regional, e.endereco AS e_endereco
      FROM levantamentos l
      LEFT JOIN escolas e ON e.inep = l.inep
      WHERE $where
      ORDER BY l.data_inicio DESC
    ''', whereArgs);

    return rows.map((row) {
      final levantamento = Levantamento.fromRow(row);
      final escola = Escola(
        inep: (row['e_inep'] as String?) ?? levantamento.inep,
        nome: (row['e_nome'] as String?) ?? '(escola não sincronizada — INEP ${levantamento.inep})',
        municipio: row['e_municipio'] as String?,
        regional: row['e_regional'] as String?,
        endereco: row['e_endereco'] as String?,
      );
      return LevantamentoComEscola(levantamento: levantamento, escola: escola);
    }).toList();
  }

  /// Levantamentos concluídos visíveis pro usuário logado (2026-09-12,
  /// cartão "Concluídos" da Home) — respeita a MESMA regra de visibilidade
  /// documentada na classe: só ADM enxerga concluído; técnico comum nunca
  /// vê um levantamento depois que ele sai de em_andamento (a não ser que
  /// seja reaberto, quando volta a status em_andamento e reaparece em
  /// [listarEmAndamento] normalmente). Por isso devolve lista vazia direto
  /// pra quem não é ADM, sem nem consultar o banco.
  ///
  /// [limite] existe pra não arriscar carregar uma lista enorme de uma vez
  /// só (647 escolas, anos de levantamentos concluídos acumulando) — se um
  /// dia isso passar a ser um problema real de verdade (mais concluídos do
  /// que o limite), a tela que usa isso precisa de paginação de verdade em
  /// vez de só aumentar o número.
  Future<List<LevantamentoComEscola>> listarConcluidos({
    required String matricula,
    required bool isAdm,
    int limite = 300,
  }) async {
    if (!isAdm) return const [];
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT
        l.id, l.inep, l.tecnico_abertura, l.data_inicio, l.lat_abertura, l.long_abertura, l.status,
        e.inep AS e_inep, e.nome AS e_nome, e.municipio AS e_municipio, e.regional AS e_regional, e.endereco AS e_endereco
      FROM levantamentos l
      LEFT JOIN escolas e ON e.inep = l.inep
      WHERE l.status = 'concluido'
      ORDER BY l.atualizado_em DESC
      LIMIT ?
    ''', [limite]);

    return rows.map((row) {
      final levantamento = Levantamento.fromRow(row);
      final escola = Escola(
        inep: (row['e_inep'] as String?) ?? levantamento.inep,
        nome: (row['e_nome'] as String?) ?? '(escola não sincronizada — INEP ${levantamento.inep})',
        municipio: row['e_municipio'] as String?,
        regional: row['e_regional'] as String?,
        endereco: row['e_endereco'] as String?,
      );
      return LevantamentoComEscola(levantamento: levantamento, escola: escola);
    }).toList();
  }

  /// Conta concluídos sem carregar a lista inteira (mesma regra de
  /// visibilidade acima) — usado no número do cartão-resumo da Home.
  Future<int> contarConcluidos({required bool isAdm}) async {
    if (!isAdm) return 0;
    final db = await AppDatabase.instance.database;
    final resultado = await db.rawQuery("SELECT COUNT(*) AS c FROM levantamentos WHERE status = 'concluido'");
    return (resultado.first['c'] as int?) ?? 0;
  }

  Future<Levantamento> criar({
    required String inep,
    required String matricula,
    double? lat,
    double? long,
  }) async {
    final db = await AppDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();
    final id = _uuid.v4();
    await db.insert('levantamentos', {
      'id': id,
      'inep': inep,
      'tecnico_abertura': matricula,
      'data_inicio': agora,
      'lat_abertura': lat,
      'long_abertura': long,
      'status': 'em_andamento',
      'ambientes_selecao_feita': 0,
      'criado_em': agora,
      'atualizado_em': agora,
      'sync_status': 'pending',
    });
    return Levantamento(
      id: id,
      inep: inep,
      tecnicoAbertura: matricula,
      dataInicio: agora,
      latAbertura: lat,
      longAbertura: long,
      status: 'em_andamento',
      ambientesSelecaoFeita: false,
    );
  }

  /// Marca que a pessoa já passou pela seleção inicial de ambientes (Tela
  /// 4), tenha ela criado algum ambiente ou escolhido "pular por enquanto".
  /// Sem isso, um levantamento sem nenhum AMBIENTE (por ter pulado) não
  /// tinha como distinguir "ainda não decidiu" de "decidiu não ter
  /// ambiente nenhum agora" — a tela voltava a mostrar a seleção pra
  /// sempre (bug relatado pelo usuário).
  Future<void> marcarSelecaoAmbientesFeita(String idLevantamento) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'levantamentos',
      {'ambientes_selecao_feita': 1, 'atualizado_em': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [idLevantamento],
    );
  }

  /// Tela 8 do spec — conclui o levantamento: muda STATUS pra `concluido`,
  /// grava quem assinou e o link da assinatura já enviada (ver
  /// ConclusaoScreen, que chama `upload_assinatura` ANTES desta função —
  /// aqui só grava o resultado). `sync_status='pending'` de propósito:
  /// como 'levantamentos' está em `_tabelasPorLevantamento`
  /// (LevantamentoSyncService), isso é suficiente pra esse levantamento
  /// entrar na fila do próximo `pushPendentes()` — nenhuma mudança extra
  /// precisou no motor de sync, ele já mandava STATUS/ID_SERVIDOR_
  /// RESPONSAVEL/DATA_ASSINATURA/ASSINATURA_URL pro servidor
  /// (`_levantamentoParaApi`), e o backend (`actionPushLevantamento`) já
  /// validava PODE_ASSINAR=true nesse caso — só faltava a tela chamar.
  Future<void> concluir({
    required String idLevantamento,
    required String idServidorResponsavel,
    required String assinaturaUrl,
  }) async {
    final db = await AppDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();
    await db.update(
      'levantamentos',
      {
        'status': 'concluido',
        'id_servidor_responsavel': idServidorResponsavel,
        'data_assinatura': agora,
        'assinatura_url': assinaturaUrl,
        'atualizado_em': agora,
        'sync_status': 'pending',
      },
      where: 'id = ?',
      whereArgs: [idLevantamento],
    );
  }
}
