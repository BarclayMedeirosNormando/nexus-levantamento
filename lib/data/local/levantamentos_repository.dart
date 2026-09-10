import 'package:uuid/uuid.dart';
import 'database.dart';

class Levantamento {
  final String id;
  final String inep;
  final String tecnicoAbertura;
  final String? dataInicio;
  final double? latAbertura;
  final double? longAbertura;
  final String status; // 'em_andamento' | 'concluido'

  const Levantamento({
    required this.id,
    required this.inep,
    required this.tecnicoAbertura,
    this.dataInicio,
    this.latAbertura,
    this.longAbertura,
    required this.status,
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
    );
  }
}

/// LEVANTAMENTOS é transacional (ver §4/§6 do spec) — criado/editado em
/// campo, marcado `sync_status='pending'` até o `push_levantamento` (que
/// ainda não existe no app; por enquanto o registro fica só local). UUID
/// gerado no cliente (`uuid` pkg) — mesma ideia do UNIQUEID() do AppSheet,
/// garante idempotência quando o sync entrar.
class LevantamentosRepository {
  static const _uuid = Uuid();

  /// Levantamento em_andamento aberto por este técnico nesta escola, se
  /// existir — ainda não considera auxiliares (LEVANTAMENTO_TECNICOS, §5b),
  /// isso entra quando a tela de auxiliares existir.
  Future<Levantamento?> buscarEmAndamento({required String inep, required String matricula}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'levantamentos',
      where: 'inep = ? AND tecnico_abertura = ? AND status = ?',
      whereArgs: [inep, matricula, 'em_andamento'],
      orderBy: 'criado_em DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Levantamento.fromRow(rows.first);
  }

  Future<List<Levantamento>> listarHistorico(String inep) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'levantamentos',
      where: 'inep = ?',
      whereArgs: [inep],
      orderBy: 'criado_em DESC',
    );
    return rows.map(Levantamento.fromRow).toList();
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
    );
  }
}
