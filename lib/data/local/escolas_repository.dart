import 'database.dart';

class Escola {
  final String inep;
  final String nome;
  final String? municipio;
  final String? regional;
  final String? endereco;

  const Escola({
    required this.inep,
    required this.nome,
    this.municipio,
    this.regional,
    this.endereco,
  });

  factory Escola.fromRow(Map<String, Object?> row) {
    return Escola(
      inep: row['inep'] as String,
      nome: row['nome'] as String,
      municipio: row['municipio'] as String?,
      regional: row['regional'] as String?,
      endereco: row['endereco'] as String?,
    );
  }
}

const _semRegional = 'Sem regional';
const _semMunicipio = 'Sem município';

class RegionalResumo {
  final String regional;
  final int totalEscolas;
  const RegionalResumo({required this.regional, required this.totalEscolas});
}

class MunicipioResumo {
  final String municipio;
  final int totalEscolas;
  const MunicipioResumo({required this.municipio, required this.totalEscolas});
}

/// Só leitura no app — ESCOLAS é tabela de referência (ver §4 do spec),
/// sempre substituída inteira a cada `pull_referencia` (SyncService). Este
/// repositório nunca escreve, só consulta o que já está no SQLite local.
class EscolasRepository {
  /// Lista escolas do banco local, opcionalmente filtrando por nome/INEP/
  /// município (busca simples, sem acento-insensitive de propósito — nomes
  /// de escola/município na base já vêm em maiúsculas e sem tratamento
  /// especial de acentuação seria mais complexidade do que vale agora).
  Future<List<Escola>> listar({String? busca}) async {
    final db = await AppDatabase.instance.database;
    List<Map<String, Object?>> rows;
    final termo = busca?.trim() ?? '';
    if (termo.isEmpty) {
      rows = await db.query('escolas', orderBy: 'nome ASC');
    } else {
      final like = '%$termo%';
      rows = await db.query(
        'escolas',
        where: 'nome LIKE ? OR inep LIKE ? OR municipio LIKE ?',
        whereArgs: [like, like, like],
        orderBy: 'nome ASC',
      );
    }
    return rows.map(Escola.fromRow).toList();
  }

  Future<int> contar() async {
    final db = await AppDatabase.instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM escolas');
    return (result.first['c'] as int?) ?? 0;
  }

  /// Navegação em árvore (Regional → Município → Escolas), a pedido do
  /// usuário — mais fácil de navegar em 647 escolas do que rolar uma lista
  /// só. `regional`/`municipio` em branco na base viram um grupo "Sem
  /// regional"/"Sem município" em vez de sumirem da contagem.
  Future<List<RegionalResumo>> listarRegionais() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(NULLIF(TRIM(regional), ''), '$_semRegional') AS regional, COUNT(*) AS total
      FROM escolas
      GROUP BY regional
      ORDER BY regional ASC
    ''');
    return rows
        .map((r) => RegionalResumo(regional: r['regional'] as String, totalEscolas: r['total'] as int))
        .toList();
  }

  Future<List<MunicipioResumo>> listarMunicipios(String regional) async {
    final db = await AppDatabase.instance.database;
    final semRegional = regional == _semRegional;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(NULLIF(TRIM(municipio), ''), '$_semMunicipio') AS municipio, COUNT(*) AS total
      FROM escolas
      WHERE ${semRegional ? "(regional IS NULL OR TRIM(regional) = '')" : 'TRIM(regional) = ?'}
      GROUP BY municipio
      ORDER BY municipio ASC
      ''',
      semRegional ? [] : [regional],
    );
    return rows
        .map((r) => MunicipioResumo(municipio: r['municipio'] as String, totalEscolas: r['total'] as int))
        .toList();
  }

  Future<List<Escola>> listarPorRegionalMunicipio(String regional, String municipio) async {
    final db = await AppDatabase.instance.database;
    final semRegional = regional == _semRegional;
    final semMunicipio = municipio == _semMunicipio;
    final where = <String>[];
    final args = <Object?>[];
    if (semRegional) {
      where.add("(regional IS NULL OR TRIM(regional) = '')");
    } else {
      where.add('TRIM(regional) = ?');
      args.add(regional);
    }
    if (semMunicipio) {
      where.add("(municipio IS NULL OR TRIM(municipio) = '')");
    } else {
      where.add('TRIM(municipio) = ?');
      args.add(municipio);
    }
    final rows = await db.query(
      'escolas',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'nome ASC',
    );
    return rows.map(Escola.fromRow).toList();
  }
}
