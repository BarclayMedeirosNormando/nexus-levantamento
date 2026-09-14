import 'package:uuid/uuid.dart';

import 'database.dart';

/// FOTOS (2026-09-14) — galeria geral do levantamento (nível da escola, não
/// amarrada a um equipamento específico como as fotos de etiqueta/equipamento
/// em `equipamentos_repository.dart`). Replica a aba FOTOS que já existia na
/// planilha "Nexus Inventario" do AppSheet: mesmos tipos observados nos dados
/// reais (ver [tipos]), incluindo "Outro" com um campo de texto livre próprio
/// ([FotoLevantamento.outroTipoFoto]). Pode ter várias fotos do mesmo tipo no
/// mesmo levantamento — galeria livre, cada foto é sua própria linha (mesma
/// ideia da aba original), não um slot único por tipo.
class FotoLevantamento {
  final String id;
  final String idLevantamento;
  final String inep;
  final String tipoFoto;
  final String? outroTipoFoto;
  final String? descricao;
  final String? fotoUrl;
  final String? fotoLocalPath;
  final String? criadoPor;
  final String? criadoEm;

  const FotoLevantamento({
    required this.id,
    required this.idLevantamento,
    required this.inep,
    required this.tipoFoto,
    this.outroTipoFoto,
    this.descricao,
    this.fotoUrl,
    this.fotoLocalPath,
    this.criadoPor,
    this.criadoEm,
  });

  /// Rótulo pra exibir na UI — "Outro: <o que a pessoa digitou>" quando
  /// aplicável, senão só o tipo.
  String get rotulo {
    if (tipoFoto == 'Outro' && outroTipoFoto != null && outroTipoFoto!.trim().isNotEmpty) {
      return 'Outro: ${outroTipoFoto!.trim()}';
    }
    return tipoFoto;
  }

  factory FotoLevantamento.fromRow(Map<String, Object?> row) {
    return FotoLevantamento(
      id: row['id'] as String,
      idLevantamento: row['id_levantamento'] as String,
      inep: row['inep'] as String,
      tipoFoto: row['tipo_foto'] as String? ?? 'Outro',
      outroTipoFoto: row['outro_tipo_foto'] as String?,
      descricao: row['descricao'] as String?,
      fotoUrl: row['foto_url'] as String?,
      fotoLocalPath: row['foto_local_path'] as String?,
      criadoPor: row['criado_por'] as String?,
      criadoEm: row['criado_em'] as String?,
    );
  }
}

class FotosLevantamentoRepository {
  static const _uuid = Uuid();

  /// Tipos disponíveis — mesmos valores reais observados na aba FOTOS da
  /// planilha "Nexus Inventario" do AppSheet (2026-09-14, confirmado
  /// conferindo o arquivo). "Outro" sempre por último, com campo de texto
  /// livre próprio na tela (ver `outro_tipo_foto`).
  static const tipos = ['Fachada', 'Laboratório', 'Roteador', 'Equipamento', 'Documento', 'Outro'];

  Future<List<FotoLevantamento>> listarPorLevantamento(String idLevantamento) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'fotos_levantamento',
      where: 'id_levantamento = ?',
      whereArgs: [idLevantamento],
      orderBy: 'criado_em DESC',
    );
    return rows.map(FotoLevantamento.fromRow).toList();
  }

  Future<void> adicionar({
    required String idLevantamento,
    required String inep,
    required String matricula,
    required String tipoFoto,
    String? outroTipoFoto,
    String? descricao,
    required String fotoLocalPath,
  }) async {
    final db = await AppDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();
    await db.insert('fotos_levantamento', {
      'id': _uuid.v4(),
      'id_levantamento': idLevantamento,
      'inep': inep,
      'tipo_foto': tipoFoto,
      'outro_tipo_foto': tipoFoto == 'Outro' ? outroTipoFoto : null,
      'descricao': descricao,
      'foto_local_path': fotoLocalPath,
      'criado_por': matricula,
      'criado_em': agora,
      'atualizado_em': agora,
      'sync_status': 'pending',
    });
  }

  Future<void> remover(String id) async {
    final db = await AppDatabase.instance.database;
    await db.delete('fotos_levantamento', where: 'id = ?', whereArgs: [id]);
  }
}
