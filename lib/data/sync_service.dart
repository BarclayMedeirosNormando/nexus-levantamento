import 'package:sqflite/sqflite.dart';
import 'local/database.dart';
import 'remote/api_client.dart';
import 'remote/auth_service.dart';

class SyncCounts {
  final int escolas;
  final int servidores;
  final int contratos;
  final int ambientesPadrao;

  const SyncCounts({
    required this.escolas,
    required this.servidores,
    required this.contratos,
    required this.ambientesPadrao,
  });
}

/// Baixa as tabelas de referência (`pull_referencia`) e substitui o cache
/// local inteiro — é sempre "replace all", nunca merge parcial, porque são
/// tabelas somente-leitura no app (a fonte da verdade é sempre a planilha).
///
/// Fica de propósito separado do AuthService/ApiClient: essa classe só
/// entende de sincronizar referência, não de autenticação nem de subir
/// levantamento (isso vai entrar depois, no PushService, quando as telas de
/// levantamento existirem).
class SyncService {
  SyncService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();
  final ApiClient _api;

  Future<SyncCounts> pullReferencia(Session session) async {
    final resposta = await _api.call('pull_referencia', {'token': session.token});

    if (resposta['ok'] == false) {
      throw ApiException(resposta['error']?.toString() ?? 'Falha ao sincronizar.');
    }

    // Nomes de campo aqui têm que bater exatamente com o que actionPullReferencia
    // devolve em claude/backend_levantamento.gs — são os nomes da API, não os
    // nomes das colunas do Sheets (esses ficam dentro de cada item da lista).
    final escolas = (resposta['escolas'] as List?) ?? const [];
    final servidores = (resposta['servidores'] as List?) ?? const [];
    final contratos = (resposta['contratos_internet'] as List?) ?? const [];
    final ambientesPadrao = (resposta['ambientes_padrao'] as List?) ?? const [];
    final catalogo = (resposta['catalogo_equipamentos'] as List?) ?? const [];
    // Nome do campo também tem que bater com actionPullReferencia — vem de
    // lerIndiceEquipamentos() no backend: só ID/INEP/TOMBAMENTO/NUM_SERIE
    // de EQUIPAMENTOS, nunca a linha inteira (aba que mais cresce).
    final indiceEquipamentos = (resposta['indice_tombamentos_serie'] as List?) ?? const [];

    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete('escolas');
      for (final e in escolas) {
        final m = e as Map<String, dynamic>;
        await txn.insert('escolas', {
          'inep': m['INEP']?.toString() ?? '',
          'nome': m['NOME']?.toString() ?? '',
          'municipio': m['MUNICIPIO']?.toString(),
          'regional': m['REGIONAL']?.toString(),
          'endereco': m['ENDERECO']?.toString(),
          'latitude': m['LATITUDE']?.toString(),
          'longitude': m['LONGITUDE']?.toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // Desde 2026-09-12, `servidores` traz a aba SERVIDORES inteira (~26-29
      // mil linhas — antes só vinha quem tinha LOGIN_HABILITADO/PODE_ASSINAR,
      // ver actionPullReferencia no backend), pra Tela 8/Conclusão poder
      // escolher qualquer responsável 100% offline. Usa `Batch` em vez de um
      // `await txn.insert(...)` por linha: bem mais rápido pra esse volume,
      // já que enfileira tudo e manda pro banco de uma vez só no commit,
      // sem uma ida-e-volta (await) por linha.
      await txn.delete('servidores');
      final batchServidores = txn.batch();
      for (final s in servidores) {
        final m = s as Map<String, dynamic>;
        batchServidores.insert('servidores', {
          'matricula': m['MATRICULA']?.toString() ?? '',
          'nome': m['NOME']?.toString() ?? '',
          'pode_assinar': (m['PODE_ASSINAR'] == true) ? 1 : 0,
          'login_habilitado': (m['LOGIN_HABILITADO'] == true) ? 1 : 0,
          'papel': m['PAPEL']?.toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batchServidores.commit(noResult: true);

      await txn.delete('contratos_internet');
      for (final c in contratos) {
        final m = c as Map<String, dynamic>;
        await txn.insert('contratos_internet', {
          'id_contrato': m['ID_CONTRATO']?.toString() ?? '',
          'inep': m['INEP']?.toString() ?? '',
          'operadora': m['OPERADORA']?.toString(),
          'plano': m['PLANO']?.toString(),
          'velocidade_contratada_mbps': m['VELOCIDADE_CONTRATADA_MBPS']?.toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.delete('ambientes_padrao');
      for (final a in ambientesPadrao) {
        final m = a as Map<String, dynamic>;
        await txn.insert('ambientes_padrao', {
          'id_tipo_ambiente': m['ID_TIPO_AMBIENTE']?.toString() ?? '',
          'nome_padrao': m['NOME_PADRAO']?.toString() ?? '',
          'obrigatorio': (m['OBRIGATORIO'] == true) ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.delete('catalogo_equipamentos');
      for (final c in catalogo) {
        final m = c as Map<String, dynamic>;
        await txn.insert('catalogo_equipamentos', {
          'id_catalogo': m['ID_CATALOGO']?.toString() ?? '',
          'tipo_equipamento': m['TIPO_EQUIPAMENTO']?.toString(),
          'marca': m['MARCA']?.toString(),
          'modelo': m['MODELO']?.toString(),
          'chave_modelo': m['CHAVE_MODELO']?.toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // Índice leve de duplicidade (Tombamento/Nº de Série) — ver
      // EquipamentosRepository.verificarDuplicidade e spec §5b/§10. Mesmo
      // padrão "replace all" das outras tabelas de referência: sempre
      // substitui inteiro pelo que veio do servidor, nunca merge parcial.
      // Uma chave por TOMBAMENTO e outra por NUM_SERIE — por isso cada
      // linha do índice pode gerar até duas entradas aqui.
      await txn.delete('indice_duplicidade');
      for (final item in indiceEquipamentos) {
        final m = item as Map<String, dynamic>;
        final id = m['ID']?.toString() ?? '';
        if (id.isEmpty) continue;
        final tombamento = m['TOMBAMENTO']?.toString().trim() ?? '';
        final numSerie = m['NUM_SERIE']?.toString().trim() ?? '';
        if (tombamento.isNotEmpty) {
          await txn.insert('indice_duplicidade', {
            'chave': 'TOMBAMENTO|${tombamento.toUpperCase()}',
            'tipo': 'TOMBAMENTO',
            'id_equipamento': id,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        if (numSerie.isNotEmpty) {
          await txn.insert('indice_duplicidade', {
            'chave': 'NUM_SERIE|${numSerie.toUpperCase()}',
            'tipo': 'NUM_SERIE',
            'id_equipamento': id,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });

    return SyncCounts(
      escolas: escolas.length,
      servidores: servidores.length,
      contratos: contratos.length,
      ambientesPadrao: ambientesPadrao.length,
    );
  }
}
