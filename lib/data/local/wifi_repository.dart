import 'package:uuid/uuid.dart';
import 'database.dart';

class RedeWifi {
  final String id;
  final String idLevantamento;
  final String inep;
  final String ssid;
  final String? senha;

  const RedeWifi({
    required this.id,
    required this.idLevantamento,
    required this.inep,
    required this.ssid,
    this.senha,
  });

  factory RedeWifi.fromRow(Map<String, Object?> row) {
    return RedeWifi(
      id: row['id'] as String,
      idLevantamento: row['id_levantamento'] as String,
      inep: row['inep'] as String,
      ssid: row['ssid'] as String? ?? '',
      senha: row['senha'] as String?,
    );
  }
}

/// WIFI (§4/§5 Tela 7b do spec) — redes wifi da escola dentro de um
/// levantamento; pode ter mais de uma (ex.: rede administrativa e rede de
/// alunos). Schema local (tabela `wifi`) e as colunas remotas (aba WIFI)
/// já existiam antes desta tela — o motor de sync (push/pull, mapeamento
/// _wifiParaApi/_wifiParaLocal em LevantamentoSyncService) já cobria wifi
/// desde o início, só faltava a tela em si.
class WifiRepository {
  static const _uuid = Uuid();

  Future<List<RedeWifi>> listarPorLevantamento(String idLevantamento) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'wifi',
      where: 'id_levantamento = ?',
      whereArgs: [idLevantamento],
      orderBy: 'criado_em ASC',
    );
    return rows.map(RedeWifi.fromRow).toList();
  }

  Future<void> criar({
    required String idLevantamento,
    required String inep,
    required String matricula,
    required String ssid,
    String? senha,
  }) async {
    final db = await AppDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();
    await db.insert('wifi', {
      'id': _uuid.v4(),
      'id_levantamento': idLevantamento,
      'inep': inep,
      'ssid': ssid,
      'senha': senha,
      'criado_por': matricula,
      'criado_em': agora,
      'atualizado_em': agora,
      'sync_status': 'pending',
    });
  }

  Future<void> atualizar({
    required String id,
    required String ssid,
    String? senha,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'wifi',
      {
        'ssid': ssid,
        'senha': senha,
        'atualizado_em': DateTime.now().toIso8601String(),
        // Edição local depois de já ter vindo sincronizada do servidor
        // precisa voltar pra fila — sem isso o próximo pull sobrescreveria
        // essa edição de volta pro valor antigo (mesma lógica de guarda de
        // _mergeLinhaSimples, ver LevantamentoSyncService).
        'sync_status': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> remover(String id) async {
    final db = await AppDatabase.instance.database;
    await db.delete('wifi', where: 'id = ?', whereArgs: [id]);
  }
}
