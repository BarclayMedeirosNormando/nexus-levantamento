import 'package:uuid/uuid.dart';
import 'database.dart';

/// '' → null. Uma célula em branco do Google Sheets chega no JSON do
/// backend como string vazia, não `null` — sem essa normalização, campos
/// tipo-enum (como `status_link`) guardavam `''` em vez de `null` depois de
/// um sync, e quebravam qualquer dropdown que espera um dos valores válidos
/// ou `null` (ver `Conectividade.fromRow`).
String? _nuloSeVazio(String? valor) => (valor == null || valor.isEmpty) ? null : valor;

class ContratoInternet {
  final String idContrato;
  final String inep;
  final String? operadora;
  final String? plano;
  final String? velocidadeContratadaMbps;

  const ContratoInternet({
    required this.idContrato,
    required this.inep,
    this.operadora,
    this.plano,
    this.velocidadeContratadaMbps,
  });

  factory ContratoInternet.fromRow(Map<String, Object?> row) {
    return ContratoInternet(
      idContrato: row['id_contrato'] as String,
      inep: row['inep'] as String,
      operadora: row['operadora'] as String?,
      plano: row['plano'] as String?,
      velocidadeContratadaMbps: row['velocidade_contratada_mbps'] as String?,
    );
  }
}

class Conectividade {
  final String id;
  final String idLevantamento;
  final String inep;
  final String tipoPagamento; // 'Estado' | 'Escola'
  final String? idContrato;
  final String? operadora;
  final String? velocidadeContratadaMbps;
  final double? velocidadeMedidaDownloadMbps;
  final double? velocidadeMedidaUploadMbps;
  final String? statusLink; // 'ATIVA' | 'INATIVA' | 'NAO_ENCONTRADA' — só Estado
  final String? idAmbiente; // só Escola

  const Conectividade({
    required this.id,
    required this.idLevantamento,
    required this.inep,
    required this.tipoPagamento,
    this.idContrato,
    this.operadora,
    this.velocidadeContratadaMbps,
    this.velocidadeMedidaDownloadMbps,
    this.velocidadeMedidaUploadMbps,
    this.statusLink,
    this.idAmbiente,
  });

  bool get isEstado => tipoPagamento == 'Estado';

  factory Conectividade.fromRow(Map<String, Object?> row) {
    return Conectividade(
      id: row['id'] as String,
      idLevantamento: row['id_levantamento'] as String,
      inep: row['inep'] as String,
      tipoPagamento: row['tipo_pagamento'] as String? ?? 'Escola',
      idContrato: row['id_contrato'] as String?,
      operadora: row['operadora'] as String?,
      velocidadeContratadaMbps: row['velocidade_contratada_mbps'] as String?,
      velocidadeMedidaDownloadMbps: (row['velocidade_medida_download_mbps'] as num?)?.toDouble(),
      velocidadeMedidaUploadMbps: (row['velocidade_medida_upload_mbps'] as num?)?.toDouble(),
      // '' vira null aqui de propósito: uma célula em branco do Sheets
      // chega do sync como string vazia (não null), e um STATUS_LINK ''
      // quebrava o dropdown de status em ConectividadeScreen (nenhum item
      // do enum bate com ''). Ver também o defensive-check espelhado lá.
      statusLink: _nuloSeVazio(row['status_link'] as String?),
      idAmbiente: row['id_ambiente'] as String?,
    );
  }
}

/// CONECTIVIDADE (§4/§5 Tela 7 do spec) — links de internet da escola dentro
/// de um levantamento; pode ter mais de um. Dois jeitos de criar:
/// - "Estado": um registro pra cada CONTRATOS_INTERNET já cadastrado da
///   escola, criado em lote com Operadora/Velocidade Contratada já vindas
///   do contrato — o técnico só completa velocidade medida e status.
/// - "Escola": formulário manual, sem contrato, pra internet que a própria
///   escola paga com recurso próprio ("escola conectada").
class ConectividadeRepository {
  static const _uuid = Uuid();

  Future<List<ContratoInternet>> listarContratosDaEscola(String inep) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('contratos_internet', where: 'inep = ?', whereArgs: [inep]);
    return rows.map(ContratoInternet.fromRow).toList();
  }

  Future<List<Conectividade>> listarPorLevantamento(String idLevantamento) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'conectividade',
      where: 'id_levantamento = ?',
      whereArgs: [idLevantamento],
      orderBy: 'criado_em ASC',
    );
    return rows.map(Conectividade.fromRow).toList();
  }

  /// Cria um registro de CONECTIVIDADE pra cada contrato da escola que ainda
  /// não tem link criado neste levantamento — evita duplicar se a pessoa
  /// tocar em "Criar Conectividade > Estado" mais de uma vez. Devolve
  /// quantos links novos foram criados (0 = nada pra adicionar: ou a escola
  /// não tem contrato nenhum cadastrado, ou todos já foram criados antes).
  Future<int> criarLinksDeEstado({
    required String idLevantamento,
    required String inep,
    required String matricula,
  }) async {
    final contratos = await listarContratosDaEscola(inep);
    if (contratos.isEmpty) return 0;
    final db = await AppDatabase.instance.database;
    final existentesRows = await db.query(
      'conectividade',
      columns: ['id_contrato'],
      where: "id_levantamento = ? AND tipo_pagamento = 'Estado'",
      whereArgs: [idLevantamento],
    );
    final existentes = existentesRows.map((r) => r['id_contrato'] as String?).whereType<String>().toSet();
    final faltantes = contratos.where((c) => !existentes.contains(c.idContrato)).toList();
    if (faltantes.isEmpty) return 0;

    final agora = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final contrato in faltantes) {
      batch.insert('conectividade', {
        'id': _uuid.v4(),
        'id_levantamento': idLevantamento,
        'inep': inep,
        'tipo_pagamento': 'Estado',
        'id_contrato': contrato.idContrato,
        'operadora': contrato.operadora,
        'velocidade_contratada_mbps': contrato.velocidadeContratadaMbps,
        'criado_por': matricula,
        'criado_em': agora,
        'atualizado_em': agora,
        'sync_status': 'pending',
      });
    }
    await batch.commit(noResult: true);
    return faltantes.length;
  }

  Future<void> criarLinkDeEscola({
    required String idLevantamento,
    required String inep,
    required String matricula,
    String? operadoraInformada,
    String? velocidadeContratadaInformada,
    double? velocidadeDownload,
    double? velocidadeUpload,
    String? idAmbiente,
  }) async {
    final db = await AppDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();
    await db.insert('conectividade', {
      'id': _uuid.v4(),
      'id_levantamento': idLevantamento,
      'inep': inep,
      'tipo_pagamento': 'Escola',
      'operadora': operadoraInformada,
      'velocidade_contratada_mbps': velocidadeContratadaInformada,
      'velocidade_medida_download_mbps': velocidadeDownload,
      'velocidade_medida_upload_mbps': velocidadeUpload,
      'id_ambiente': idAmbiente,
      'criado_por': matricula,
      'criado_em': agora,
      'atualizado_em': agora,
      'sync_status': 'pending',
    });
  }

  Future<void> atualizarLinkEscola({
    required String id,
    String? operadoraInformada,
    String? velocidadeContratadaInformada,
    double? velocidadeDownload,
    double? velocidadeUpload,
    String? idAmbiente,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'conectividade',
      {
        'operadora': operadoraInformada,
        'velocidade_contratada_mbps': velocidadeContratadaInformada,
        'velocidade_medida_download_mbps': velocidadeDownload,
        'velocidade_medida_upload_mbps': velocidadeUpload,
        'id_ambiente': idAmbiente,
        'atualizado_em': DateTime.now().toIso8601String(),
        // Edição local depois de já ter vindo sincronizada do servidor
        // precisa voltar pra fila — sem isso o próximo pull sobrescreveria
        // essa edição de volta pro valor antigo (mesma lógica de guarda em
        // WifiRepository.atualizar / bug relatado pelo Barclay: dado de
        // Conectividade editado não subia).
        'sync_status': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> atualizarMedicaoEstado({
    required String id,
    double? velocidadeDownload,
    double? velocidadeUpload,
    String? statusLink,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'conectividade',
      {
        'velocidade_medida_download_mbps': velocidadeDownload,
        'velocidade_medida_upload_mbps': velocidadeUpload,
        'status_link': statusLink,
        'atualizado_em': DateTime.now().toIso8601String(),
        // Mesmo motivo do comentário em atualizarLinkEscola acima.
        'sync_status': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> remover(String id) async {
    final db = await AppDatabase.instance.database;
    await db.delete('conectividade', where: 'id = ?', whereArgs: [id]);
  }
}
