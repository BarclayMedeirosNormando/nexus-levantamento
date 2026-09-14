import 'package:sqflite/sqflite.dart';
import 'local/database.dart';
import 'remote/api_client.dart';
import 'remote/auth_service.dart';

class PushResult {
  final int levantamentosEnviados;
  final List<dynamic> avisos;
  const PushResult({required this.levantamentosEnviados, required this.avisos});
}

class PullAtivosResult {
  final int levantamentos;
  final int ambientes;
  final int auxiliares;
  const PullAtivosResult({required this.levantamentos, required this.ambientes, required this.auxiliares});
}

/// Sobe (`push_levantamento`) e baixa (`pull_levantamentos_ativos`) o que é
/// transacional — LEVANTAMENTOS e tudo dentro dele (ambientes, auxiliares,
/// equipamentos, inserviveis, conectividade, wifi). É a metade que faltava
/// do motor de sincronização (§5b/§6 do spec): até aqui, o app só sabia
/// baixar referência (`SyncService.pullReferencia` — escolas, servidores,
/// contratos) e nunca tinha subido levantamento nenhum. Sem isso, um
/// auxiliar adicionado num levantamento só existia no aparelho de quem
/// abriu — cada aparelho só conhece o que foi criado nele mesmo, localmente,
/// até sincronizar.
///
/// Os dois endpoints já existiam prontos no backend (`push_levantamento` e
/// `pull_levantamentos_ativos`, com todas as validações de autorização) —
/// só faltava o app chamar.
///
/// Fica separado do `SyncService` de propósito: são dois motores com regra
/// de conflito diferente. Referência é sempre "replace all" vindo do
/// servidor (tabela só-leitura no app). Aqui é merge — cada aparelho pode
/// ter dado próprio ainda não sincronizado (`sync_status = 'pending'`) que
/// nunca pode ser pisado por um pull.
///
/// Caveat conhecido (não resolvido aqui): remover um auxiliar é hoje uma
/// operação só local (`AuxiliaresRepository.remover` apaga a linha na hora,
/// sem passar por `sync_status`) — o backend (`actionPushLevantamento`) só
/// ADICIONA auxiliar que ainda não existe lá, nunca remove. Ou seja: tirar
/// um auxiliar aqui não é comunicado pro servidor, e um próximo pull pode
/// trazer esse auxiliar de volta se outro aparelho (ou o servidor) ainda o
/// tiver. Resolver isso direito exigiria endpoint próprio de remoção —
/// fica como próxima pendência, fora do escopo de "fazer o básico sincronizar".
class LevantamentoSyncService {
  LevantamentoSyncService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();
  final ApiClient _api;

  static const _tabelasPorLevantamento = [
    'levantamentos',
    'levantamento_tecnicos',
    'ambientes',
    'equipamentos',
    'equipamentos_inserviveis',
    'conectividade',
    'wifi',
    'fotos_levantamento',
    'atividades',
  ];

  // ---------------------------------------------------------------------
  // PUSH
  // ---------------------------------------------------------------------

  /// Sobe pro servidor todo levantamento que tiver QUALQUER pendência
  /// (`sync_status = 'pending'`) em qualquer uma das tabelas ligadas a ele.
  /// Um POST por levantamento — é como o endpoint foi desenhado, recebe o
  /// levantamento inteiro + tudo dentro dele de uma vez. Manda sempre o
  /// estado local INTEIRO daquele levantamento (não só as linhas
  /// pendentes) — o upsert do servidor é idempotente, reenviar o que já
  /// estava sincronizado não corrompe nada, só simplifica a lógica aqui.
  Future<PushResult> pushPendentes(Session session) async {
    final db = await AppDatabase.instance.database;
    final idsComPendencia = await _idsLevantamentosComPendencia(db);

    var enviados = 0;
    final avisos = <dynamic>[];

    for (final idLevantamento in idsComPendencia) {
      final lvRows = await db.query('levantamentos', where: 'id = ?', whereArgs: [idLevantamento], limit: 1);
      if (lvRows.isEmpty) continue; // não deveria acontecer — não trava o lote todo por um registro órfão
      final lv = lvRows.first;

      final payload = {
        'token': session.token,
        'levantamento': _levantamentoParaApi(lv),
        'tecnicos_auxiliares': await _auxiliaresParaApi(db, idLevantamento),
        'ambientes': await _linhasParaApi(db, 'ambientes', idLevantamento, _ambienteParaApi),
        'equipamentos': await _linhasParaApi(db, 'equipamentos', idLevantamento, _equipamentoParaApi),
        'equipamentos_inserviveis': await _linhasParaApi(db, 'equipamentos_inserviveis', idLevantamento, _inservivelParaApi),
        'conectividade': await _linhasParaApi(db, 'conectividade', idLevantamento, _conectividadeParaApi),
        'wifi': await _linhasParaApi(db, 'wifi', idLevantamento, _wifiParaApi),
        'fotos': await _linhasParaApi(db, 'fotos_levantamento', idLevantamento, _fotoParaApi),
        'atividades': await _linhasParaApi(db, 'atividades', idLevantamento, _atividadeParaApi),
      };

      final resposta = await _api.call('push_levantamento', payload);
      if (resposta['ok'] == false) {
        throw ApiException(
          'Falha ao sincronizar um levantamento (INEP ${lv['inep']}): ${resposta['error'] ?? 'erro desconhecido'}',
        );
      }

      await db.transaction((txn) async {
        for (final tabela in _tabelasPorLevantamento) {
          final coluna = tabela == 'levantamentos' ? 'id' : 'id_levantamento';
          await txn.update(
            tabela,
            {'sync_status': 'synced'},
            where: '$coluna = ?',
            whereArgs: [idLevantamento],
          );
        }
      });

      enviados++;
      final avisosResposta = resposta['avisos'];
      if (avisosResposta is List) avisos.addAll(avisosResposta);
    }

    return PushResult(levantamentosEnviados: enviados, avisos: avisos);
  }

  /// Conta quantos levantamentos têm QUALQUER pendência de sync — mesma
  /// checagem usada por [pushPendentes] pra decidir o que enviar, só que
  /// sem mandar nada pro servidor (2026-09-12, indicador de pendências da
  /// Home — o técnico via as informações sumirem/aparecerem sem saber se
  /// já tinha ido pro servidor ou não).
  Future<int> contarPendentes() async {
    final db = await AppDatabase.instance.database;
    final ids = await _idsLevantamentosComPendencia(db);
    return ids.length;
  }

  Future<List<String>> _idsLevantamentosComPendencia(Database db) async {
    final ids = <String>{};
    for (final tabela in _tabelasPorLevantamento) {
      final coluna = tabela == 'levantamentos' ? 'id' : 'id_levantamento';
      final rows = await db.query(tabela, columns: [coluna], where: "sync_status = 'pending'", distinct: true);
      for (final row in rows) {
        final valor = row[coluna] as String?;
        if (valor != null) ids.add(valor);
      }
    }
    return ids.toList();
  }

  Future<List<Map<String, dynamic>>> _linhasParaApi(
    Database db,
    String tabela,
    String idLevantamento,
    Map<String, dynamic> Function(Map<String, Object?> row) converter,
  ) async {
    final rows = await db.query(tabela, where: 'id_levantamento = ?', whereArgs: [idLevantamento]);
    return rows.map(converter).toList();
  }

  Future<List<String>> _auxiliaresParaApi(Database db, String idLevantamento) async {
    final rows = await db.query('levantamento_tecnicos', where: 'id_levantamento = ?', whereArgs: [idLevantamento]);
    return rows.map((r) => r['matricula_tecnico'] as String).toList();
  }

  Map<String, dynamic> _levantamentoParaApi(Map<String, Object?> row) => {
        'ID': row['id'],
        'INEP': row['inep'],
        'DATA_INICIO': row['data_inicio'],
        'LAT_ABERTURA': row['lat_abertura'],
        'LONG_ABERTURA': row['long_abertura'],
        'STATUS': row['status'],
        'ID_SERVIDOR_RESPONSAVEL': row['id_servidor_responsavel'],
        'DATA_ASSINATURA': row['data_assinatura'],
        'ASSINATURA_URL': row['assinatura_url'],
        // TECNICO_ABERTURA, REABERTO_POR e DATA_REABERTURA nunca são
        // mandados — o servidor decide/preserva esses três campos sozinho
        // (ver actionPushLevantamento no backend); mandar o valor local
        // aqui seria ignorado mesmo.
      };

  Map<String, dynamic> _ambienteParaApi(Map<String, Object?> row) => {
        'ID': row['id'],
        'ID_TIPO_AMBIENTE': row['id_tipo_ambiente'],
        'NOME_AMBIENTE': row['nome_ambiente'],
        'ORIGEM': row['origem'],
        'CRIADO_POR': row['criado_por'],
      };

  Map<String, dynamic> _equipamentoParaApi(Map<String, Object?> row) => {
        'ID': row['id'],
        'ID_AMBIENTE': row['id_ambiente'],
        'TIPO_EQUIPAMENTO': row['tipo_equipamento'],
        'MARCA': row['marca'],
        'MODELO': row['modelo'],
        'OUTRO_MODELO': row['outro_modelo'],
        'TOMBAMENTO': row['tombamento'],
        'NUM_SERIE': row['num_serie'],
        'FOTO_ETIQUETA_URL': row['foto_etiqueta_url'],
        'FOTO_EQUIPAMENTO_URL': row['foto_equipamento_url'],
        'ESTADO': row['estado'],
        'CRIADO_POR': row['criado_por'],
        // ID_CATALOGO/CHAVE_MODELO são recalculados pelo próprio servidor a
        // cada push (processarCatalogo) — não precisa mandar.
      };

  Map<String, dynamic> _inservivelParaApi(Map<String, Object?> row) => {
        'ID': row['id'],
        'ID_AMBIENTE': row['id_ambiente'],
        'TIPO_EQUIPAMENTO': row['tipo_equipamento'],
        'MARCA': row['marca'],
        'MODELO': row['modelo'],
        'QUANTIDADE': row['quantidade'],
        'CRIADO_POR': row['criado_por'],
      };

  Map<String, dynamic> _conectividadeParaApi(Map<String, Object?> row) => {
        'ID': row['id'],
        'TIPO_PAGAMENTO': row['tipo_pagamento'],
        'ID_CONTRATO': row['id_contrato'],
        'OPERADORA': row['operadora'],
        'VELOCIDADE_CONTRATADA_MBPS': row['velocidade_contratada_mbps'],
        'VELOCIDADE_MEDIDA_DOWNLOAD_MBPS': row['velocidade_medida_download_mbps'],
        'VELOCIDADE_MEDIDA_UPLOAD_MBPS': row['velocidade_medida_upload_mbps'],
        'STATUS_LINK': row['status_link'],
        'ID_AMBIENTE': row['id_ambiente'],
        'CRIADO_POR': row['criado_por'],
      };

  Map<String, dynamic> _wifiParaApi(Map<String, Object?> row) => {
        'ID': row['id'],
        'SSID': row['ssid'],
        'SENHA': row['senha'],
        'CRIADO_POR': row['criado_por'],
      };

  Map<String, dynamic> _fotoParaApi(Map<String, Object?> row) => {
        'ID': row['id'],
        'TIPO_FOTO': row['tipo_foto'],
        'OUTRO_TIPO_FOTO': row['outro_tipo_foto'],
        'DESCRICAO': row['descricao'],
        'FOTO_URL': row['foto_url'],
        'CRIADO_POR': row['criado_por'],
        // foto_local_path nunca vai pro servidor — é só o caminho do
        // arquivo neste aparelho (ver FotosLevantamentoRepository).
      };

  Map<String, dynamic> _atividadeParaApi(Map<String, Object?> row) => {
        'ID': row['id'],
        'MATRICULA': row['matricula'],
        'NOME_TECNICO': row['nome_tecnico'],
        'TIPO_ENTIDADE': row['tipo_entidade'],
        'ACAO': row['acao'],
        'DESCRICAO': row['descricao'],
        'CRIADO_EM': row['criado_em'],
      };

  // ---------------------------------------------------------------------
  // REABRIR (ADM)
  // ---------------------------------------------------------------------

  /// Reabre um levantamento concluído (2026-09-14) — faltava por completo
  /// no app: o backend (`actionReabrirLevantamento`) já existia pronto, mas
  /// nenhuma tela chamava. Pede re-autenticação do ADM (matrícula+senha),
  /// igual o próprio backend exige — não usa `session.token`: o servidor
  /// reautentica do zero, não confia na sessão já aberta pra essa ação
  /// (mesmo raciocínio de `actionResetarSenha`/reabrir ser um ato sensível).
  /// Depois do servidor confirmar, atualiza o registro local na hora (não
  /// espera o próximo pull) — assim some da lista de Concluídos
  /// imediatamente; um pull seguinte traz REABERTO_POR/DATA_REABERTURA
  /// definitivos, mas isso não bloqueia a UI aqui.
  Future<void> reabrirLevantamento({
    required String idLevantamento,
    required String matriculaAdm,
    required String senhaAdm,
  }) async {
    final resposta = await _api.call('reabrir_levantamento', {
      'id_levantamento': idLevantamento,
      'matricula_adm': matriculaAdm,
      'senha_adm': senhaAdm,
    });
    if (resposta['ok'] != true) {
      throw ApiException(resposta['error']?.toString() ?? 'Não foi possível reabrir o levantamento.');
    }

    final db = await AppDatabase.instance.database;
    await db.update(
      'levantamentos',
      {'status': 'em_andamento', 'sync_status': 'synced'},
      where: 'id = ?',
      whereArgs: [idLevantamento],
    );
  }

  // ---------------------------------------------------------------------
  // PULL
  // ---------------------------------------------------------------------

  /// Baixa os levantamentos onde o usuário logado é dono ou auxiliar (ou
  /// todos, se ADM) e mescla com o que já existe localmente. Regra de
  /// conflito (§5b do spec): uma linha com pendência local ainda não
  /// sincronizada nunca é sobrescrita por uma vinda do pull — fica como
  /// está até ser enviada no próximo push; só depois disso um próximo pull
  /// traz a versão "oficial" já mesclada. Uma linha já sincronizada é
  /// livremente atualizada com o que veio do servidor (pode ter mudado lá
  /// por causa de um colega auxiliar).
  Future<PullAtivosResult> pullLevantamentosAtivos(Session session) {
    return _pullEMesclar('pull_levantamentos_ativos', session);
  }

  /// Mesma mecânica de pull+merge do de cima, só que pros levantamentos já
  /// CONCLUÍDOS (2026-09-14) — bug real relatado pelo Barclay: como ADM,
  /// "Concluídos" nunca aparecia, a menos que tivesse sido concluído no
  /// PRÓPRIO aparelho dele. Causa: `pull_levantamentos_ativos` no backend
  /// nunca devolvia STATUS='concluido' pra ninguém (nem ADM) — pensado só
  /// pro fluxo de levantamento em andamento. Este é um pull SEPARADO
  /// (endpoint próprio `pull_levantamentos_concluidos`, só ADM — o backend
  /// também revalida isso, ver actionPullLevantamentosConcluidos), chamado
  /// só no sync completo (`SyncEngine.sincronizarTudo`), nunca no polling
  /// de 25s de `LevantamentoScreen` (que só cuida do levantamento
  /// em_andamento aberto agora — nem precisaria disto).
  Future<PullAtivosResult> pullLevantamentosConcluidos(Session session) {
    if (!session.isAdm) {
      return Future.value(const PullAtivosResult(levantamentos: 0, ambientes: 0, auxiliares: 0));
    }
    return _pullEMesclar('pull_levantamentos_concluidos', session);
  }

  Future<PullAtivosResult> _pullEMesclar(String acao, Session session) async {
    final resposta = await _api.call(acao, {'token': session.token});
    if (resposta['ok'] == false) {
      throw ApiException(resposta['error']?.toString() ?? 'Falha ao baixar levantamentos.');
    }

    final levantamentos = (resposta['levantamentos'] as List?) ?? const [];
    final auxiliares = (resposta['tecnicos_auxiliares'] as List?) ?? const [];
    final ambientes = (resposta['ambientes'] as List?) ?? const [];
    final equipamentos = (resposta['equipamentos'] as List?) ?? const [];
    final inserviveis = (resposta['equipamentos_inserviveis'] as List?) ?? const [];
    final conectividade = (resposta['conectividade'] as List?) ?? const [];
    final wifi = (resposta['wifi'] as List?) ?? const [];
    final fotos = (resposta['fotos'] as List?) ?? const [];
    final atividades = (resposta['atividades'] as List?) ?? const [];

    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      for (final item in levantamentos) {
        await _mergeLevantamento(txn, item as Map<String, dynamic>);
      }
      for (final item in ambientes) {
        await _mergeLinhaSimples(txn, 'ambientes', item as Map<String, dynamic>, _ambienteParaLocal);
      }
      for (final item in equipamentos) {
        await _mergeLinhaSimples(txn, 'equipamentos', item as Map<String, dynamic>, _equipamentoParaLocal);
      }
      for (final item in inserviveis) {
        await _mergeLinhaSimples(txn, 'equipamentos_inserviveis', item as Map<String, dynamic>, _inservivelParaLocal);
      }
      for (final item in conectividade) {
        await _mergeLinhaSimples(txn, 'conectividade', item as Map<String, dynamic>, _conectividadeParaLocal);
      }
      for (final item in wifi) {
        await _mergeLinhaSimples(txn, 'wifi', item as Map<String, dynamic>, _wifiParaLocal);
      }
      for (final item in fotos) {
        await _mergeLinhaSimples(txn, 'fotos_levantamento', item as Map<String, dynamic>, _fotoParaLocal);
      }
      for (final item in atividades) {
        await _mergeLinhaSimples(txn, 'atividades', item as Map<String, dynamic>, _atividadeParaLocal);
      }
      for (final item in auxiliares) {
        await _mergeAuxiliar(txn, item as Map<String, dynamic>);
      }
    });

    return PullAtivosResult(
      levantamentos: levantamentos.length,
      ambientes: ambientes.length,
      auxiliares: auxiliares.length,
    );
  }

  // Célula vazia numa planilha do Sheets costuma voltar como string vazia
  // (`''`), não `null` — um `as num?` direto quebraria em runtime nesse
  // caso (GPS/medição opcional nunca preenchida). Aceita number OU string
  // numérica, e trata vazio como ausente.
  // Uma célula em branco no Google Sheets chega aqui como string vazia
  // ('', via getValues() no Apps Script), não `null` — pra campos tipo-enum
  // como STATUS_LINK isso guardava '' no SQLite local em vez de null,
  // quebrando o dropdown de status em ConectividadeScreen (nenhum item do
  // enum bate com ''). Ver também `Conectividade.fromRow`, que faz a mesma
  // normalização pra dados que já estavam salvos localmente antes deste fix.
  dynamic _paraNuloSeVazio(dynamic valor) {
    if (valor is String && valor.trim().isEmpty) return null;
    return valor;
  }

  double? _paraDouble(dynamic valor) {
    if (valor == null) return null;
    if (valor is num) return valor.toDouble();
    if (valor is String) {
      final texto = valor.trim();
      if (texto.isEmpty) return null;
      return double.tryParse(texto.replaceAll(',', '.'));
    }
    return null;
  }

  Future<void> _mergeLevantamento(Transaction txn, Map<String, dynamic> remoto) async {
    final id = remoto['ID']?.toString();
    if (id == null || id.isEmpty) return;
    final locais = await txn.query('levantamentos', where: 'id = ?', whereArgs: [id], limit: 1);
    if (locais.isNotEmpty && locais.first['sync_status'] == 'pending') return; // mantém pendência local

    // `ambientes_selecao_feita` não existe no servidor (é controle só do
    // app — ver database.dart). Só é decidido na primeira vez que esse
    // levantamento aparece neste aparelho: se veio de outro técnico,
    // assume que a seleção já foi decidida lá (`1`); se já existia aqui,
    // preserva o valor local.
    final selecaoFeita = locais.isNotEmpty ? (locais.first['ambientes_selecao_feita'] as int? ?? 1) : 1;

    final valores = {
      'id': id,
      'inep': remoto['INEP'],
      'tecnico_abertura': remoto['TECNICO_ABERTURA'],
      'data_inicio': remoto['DATA_INICIO']?.toString(),
      'lat_abertura': _paraDouble(remoto['LAT_ABERTURA']),
      'long_abertura': _paraDouble(remoto['LONG_ABERTURA']),
      'status': remoto['STATUS'],
      'id_servidor_responsavel': remoto['ID_SERVIDOR_RESPONSAVEL'],
      'data_assinatura': remoto['DATA_ASSINATURA']?.toString(),
      'assinatura_url': remoto['ASSINATURA_URL'],
      'reaberto_por': remoto['REABERTO_POR'],
      'data_reabertura': remoto['DATA_REABERTURA']?.toString(),
      'criado_em': remoto['CRIADO_EM']?.toString(),
      'atualizado_em': remoto['ATUALIZADO_EM']?.toString(),
      'sync_status': 'synced',
      'ambientes_selecao_feita': selecaoFeita,
    };
    await txn.insert('levantamentos', valores, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _mergeLinhaSimples(
    Transaction txn,
    String tabela,
    Map<String, dynamic> remoto,
    Map<String, Object?> Function(Map<String, dynamic> remoto) converter,
  ) async {
    final id = remoto['ID']?.toString();
    if (id == null || id.isEmpty) return;
    final locais = await txn.query(tabela, where: 'id = ?', whereArgs: [id], limit: 1);
    if (locais.isNotEmpty && locais.first['sync_status'] == 'pending') return;

    final valores = converter(remoto);
    valores['sync_status'] = 'synced';
    await txn.insert(tabela, valores, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Map<String, Object?> _ambienteParaLocal(Map<String, dynamic> remoto) => {
        'id': remoto['ID'],
        'id_levantamento': remoto['ID_LEVANTAMENTO'],
        'inep': remoto['INEP'],
        'id_tipo_ambiente': remoto['ID_TIPO_AMBIENTE'],
        'nome_ambiente': remoto['NOME_AMBIENTE'],
        'origem': remoto['ORIGEM'],
        'criado_por': remoto['CRIADO_POR'],
        'criado_em': remoto['CRIADO_EM']?.toString(),
        'atualizado_em': remoto['ATUALIZADO_EM']?.toString(),
      };

  Map<String, Object?> _equipamentoParaLocal(Map<String, dynamic> remoto) => {
        'id': remoto['ID'],
        'id_ambiente': remoto['ID_AMBIENTE'],
        'id_levantamento': remoto['ID_LEVANTAMENTO'],
        'inep': remoto['INEP'],
        'id_catalogo': remoto['ID_CATALOGO'],
        'tipo_equipamento': remoto['TIPO_EQUIPAMENTO'],
        'marca': remoto['MARCA'],
        'modelo': remoto['MODELO'],
        'outro_modelo': remoto['OUTRO_MODELO'],
        'tombamento': remoto['TOMBAMENTO'],
        'num_serie': remoto['NUM_SERIE'],
        'foto_etiqueta_url': remoto['FOTO_ETIQUETA_URL'],
        'foto_equipamento_url': remoto['FOTO_EQUIPAMENTO_URL'],
        'estado': remoto['ESTADO'],
        'chave_modelo': remoto['CHAVE_MODELO'],
        'criado_por': remoto['CRIADO_POR'],
        'criado_em': remoto['CRIADO_EM']?.toString(),
        'atualizado_em': remoto['ATUALIZADO_EM']?.toString(),
      };

  Map<String, Object?> _inservivelParaLocal(Map<String, dynamic> remoto) => {
        'id': remoto['ID'],
        'id_ambiente': remoto['ID_AMBIENTE'],
        'id_levantamento': remoto['ID_LEVANTAMENTO'],
        'inep': remoto['INEP'],
        'tipo_equipamento': remoto['TIPO_EQUIPAMENTO'],
        'marca': remoto['MARCA'],
        'modelo': remoto['MODELO'],
        'quantidade': remoto['QUANTIDADE'],
        'criado_por': remoto['CRIADO_POR'],
        'criado_em': remoto['CRIADO_EM']?.toString(),
        'atualizado_em': remoto['ATUALIZADO_EM']?.toString(),
      };

  Map<String, Object?> _conectividadeParaLocal(Map<String, dynamic> remoto) => {
        'id': remoto['ID'],
        'id_levantamento': remoto['ID_LEVANTAMENTO'],
        'inep': remoto['INEP'],
        'tipo_pagamento': remoto['TIPO_PAGAMENTO'],
        'id_contrato': remoto['ID_CONTRATO'],
        'operadora': remoto['OPERADORA'],
        'velocidade_contratada_mbps': remoto['VELOCIDADE_CONTRATADA_MBPS'],
        'velocidade_medida_download_mbps': _paraDouble(remoto['VELOCIDADE_MEDIDA_DOWNLOAD_MBPS']),
        'velocidade_medida_upload_mbps': _paraDouble(remoto['VELOCIDADE_MEDIDA_UPLOAD_MBPS']),
        'status_link': _paraNuloSeVazio(remoto['STATUS_LINK']),
        'id_ambiente': remoto['ID_AMBIENTE'],
        'criado_por': remoto['CRIADO_POR'],
        'criado_em': remoto['CRIADO_EM']?.toString(),
        'atualizado_em': remoto['ATUALIZADO_EM']?.toString(),
      };

  Map<String, Object?> _wifiParaLocal(Map<String, dynamic> remoto) => {
        'id': remoto['ID'],
        'id_levantamento': remoto['ID_LEVANTAMENTO'],
        'inep': remoto['INEP'],
        'ssid': remoto['SSID'],
        'senha': remoto['SENHA'],
        'criado_por': remoto['CRIADO_POR'],
        'criado_em': remoto['CRIADO_EM']?.toString(),
        'atualizado_em': remoto['ATUALIZADO_EM']?.toString(),
      };

  // foto_local_path fica de fora de propósito (não existe no servidor —
  // ver _fotoParaApi). Mesmo caveat já conhecido do merge de equipamentos
  // (_equipamentoParaLocal também não inclui os *_local_path): se este
  // aparelho tiver tirado a foto mas ainda não subido (upload falhou/sem
  // tempo) E o próprio push já tiver marcado a linha como 'synced' antes do
  // upload terminar, um pull seguinte pode apagar a referência ao arquivo
  // local ainda não enviado. Janela estreita (upload roda ANTES do push no
  // SyncEngine — ver sincronizarTudo), não resolvida aqui; mesma pendência
  // que já existia pras fotos de equipamento.
  Map<String, Object?> _fotoParaLocal(Map<String, dynamic> remoto) => {
        'id': remoto['ID'],
        'id_levantamento': remoto['ID_LEVANTAMENTO'],
        'inep': remoto['INEP'],
        'tipo_foto': remoto['TIPO_FOTO'],
        'outro_tipo_foto': remoto['OUTRO_TIPO_FOTO'],
        'descricao': remoto['DESCRICAO'],
        'foto_url': remoto['FOTO_URL'],
        'criado_por': remoto['CRIADO_POR'],
        'criado_em': remoto['CRIADO_EM']?.toString(),
        'atualizado_em': remoto['ATUALIZADO_EM']?.toString(),
      };

  Map<String, Object?> _atividadeParaLocal(Map<String, dynamic> remoto) => {
        'id': remoto['ID'],
        'id_levantamento': remoto['ID_LEVANTAMENTO'],
        'inep': remoto['INEP'],
        'matricula': remoto['MATRICULA'],
        'nome_tecnico': remoto['NOME_TECNICO'],
        'tipo_entidade': remoto['TIPO_ENTIDADE'],
        'acao': remoto['ACAO'],
        'descricao': remoto['DESCRICAO'],
        'criado_em': remoto['CRIADO_EM']?.toString(),
      };

  Future<void> _mergeAuxiliar(Transaction txn, Map<String, dynamic> remoto) async {
    final idLevantamento = remoto['ID_LEVANTAMENTO']?.toString();
    final matricula = remoto['MATRICULA_TECNICO']?.toString();
    if (idLevantamento == null || matricula == null || idLevantamento.isEmpty || matricula.isEmpty) return;

    final locais = await txn.query(
      'levantamento_tecnicos',
      where: 'id_levantamento = ? AND matricula_tecnico = ?',
      whereArgs: [idLevantamento, matricula],
      limit: 1,
    );
    if (locais.isNotEmpty && locais.first['sync_status'] == 'pending') return;

    await txn.insert(
      'levantamento_tecnicos',
      {
        'id_levantamento': idLevantamento,
        'matricula_tecnico': matricula,
        'adicionado_em': remoto['ADICIONADO_EM']?.toString(),
        'sync_status': 'synced',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
