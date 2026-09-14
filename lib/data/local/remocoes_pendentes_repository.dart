import 'package:uuid/uuid.dart';

import 'database.dart';

/// Tombstone de remoção pendente (2026-09-14) — fecha o gap raiz do bug
/// "removo um ambiente e ele volta sozinho depois de uns segundos"
/// (relatado pelo Barclay). Até aqui, remover qualquer coisa (Ambiente,
/// Equipamento, Inservível, Conectividade, Wifi, Foto — tudo que tem
/// `remover()`/`removerComCascata()`) só apagava a linha local, sem NENHUM
/// registro de que aquilo precisava ser comunicado pro servidor —
/// `upsertRows()` no backend nunca apaga linha (só insere/atualiza). Um
/// item já sincronizado, removido aqui, continuava intacto na planilha, e
/// o PRÓXIMO pull (inclusive o polling de 25s do próprio aparelho, ver
/// LevantamentoScreen) trazia ele de volta.
///
/// Cada `registrar()` aqui é uma promessa: "essa linha (tabela local X, id
/// Y) precisa ser apagada no servidor também". `LevantamentoSyncService`
/// manda essas promessas no próximo `pushPendentes` (campo `remocoes` do
/// payload, backend processa em `deletarLinhasPorId`) e só apaga a
/// promessa daqui DEPOIS do servidor confirmar (mesma transação que marca
/// as outras tabelas como 'synced'). Enquanto uma promessa continuar
/// aqui, o merge de um pull (`_mergeLinhaSimples`) recusa reinserir
/// aquela linha — mesmo que o servidor ainda não tenha apagado (push
/// ainda não rodou, ou falhou por falta de rede). É essa checagem que
/// fecha de vez a janela do polling de 25s, sem depender de o push
/// terminar antes do próximo pull.
///
/// Sem `sync_status`: não é uma linha "pendente de virar synced", é uma
/// pendência que só desaparece (é apagada de vez) quando cumprida.
class RemocaoPendente {
  final String id;
  final String tabela; // nome da TABELA LOCAL (sqlite) — ex.: 'ambientes'
  final String idRegistro; // id da linha removida naquela tabela
  final String idLevantamento;

  const RemocaoPendente({
    required this.id,
    required this.tabela,
    required this.idRegistro,
    required this.idLevantamento,
  });

  factory RemocaoPendente.fromRow(Map<String, Object?> row) => RemocaoPendente(
        id: row['id'] as String,
        tabela: row['tabela'] as String,
        idRegistro: row['id_registro'] as String,
        idLevantamento: row['id_levantamento'] as String,
      );
}

class RemocoesPendentesRepository {
  static const _uuid = Uuid();

  /// Grava uma promessa de remoção — chamado de dentro do `remover()`/
  /// `removerComCascata()` de cada repositório, junto com o delete local
  /// (mesma transação, quando o método já usa uma).
  Future<void> registrar({
    required String tabela,
    required String idRegistro,
    required String idLevantamento,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.insert('remocoes_pendentes', {
      'id': _uuid.v4(),
      'tabela': tabela,
      'id_registro': idRegistro,
      'id_levantamento': idLevantamento,
      'criado_em': DateTime.now().toIso8601String(),
    });
  }

  Future<List<RemocaoPendente>> listarPorLevantamento(String idLevantamento) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('remocoes_pendentes', where: 'id_levantamento = ?', whereArgs: [idLevantamento]);
    return rows.map(RemocaoPendente.fromRow).toList();
  }

  /// IDs de levantamento com QUALQUER remoção ainda não confirmada pelo
  /// servidor — usado por `LevantamentoSyncService._idsLevantamentosComPendencia`.
  /// Sem isso, remover o ÚNICO item pendente de um levantamento (a própria
  /// linha que carregava `sync_status = 'pending'` já sumiu com o delete)
  /// fazia esse levantamento parar de ser considerado pendente, e a
  /// remoção nunca chegava a ser enviada.
  Future<Set<String>> idsLevantamentosComPendencia() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('remocoes_pendentes', columns: ['id_levantamento'], distinct: true);
    return rows.map((r) => r['id_levantamento'] as String).toSet();
  }
}
