import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'atividades_repository.dart';
import 'database.dart';
import 'remocoes_pendentes_repository.dart';

class Equipamento {
  final String id;
  final String idAmbiente;
  final String idLevantamento;
  final String inep;
  final String? idCatalogo;
  final String tipoEquipamento;
  final String? marca;
  final String? modelo;
  final String? outroModelo;
  final String? tombamento;
  final String? numSerie;
  final String? estado;
  final String? criadoPor;
  final String? fotoEtiquetaUrl;
  final String? fotoEquipamentoUrl;
  // Caminho do arquivo LOCAL (neste aparelho) — nunca vai pro servidor, só
  // existe até o FotoUploadService subir a foto e preencher a URL acima.
  // Ver comentário de `_dbVersion = 3` em database.dart.
  final String? fotoEtiquetaLocalPath;
  final String? fotoEquipamentoLocalPath;

  const Equipamento({
    required this.id,
    required this.idAmbiente,
    required this.idLevantamento,
    required this.inep,
    this.idCatalogo,
    required this.tipoEquipamento,
    this.marca,
    this.modelo,
    this.outroModelo,
    this.tombamento,
    this.numSerie,
    this.estado,
    this.criadoPor,
    this.fotoEtiquetaUrl,
    this.fotoEquipamentoUrl,
    this.fotoEtiquetaLocalPath,
    this.fotoEquipamentoLocalPath,
  });

  /// Modelo "efetivo" pra exibir — OUTRO_MODELO (texto livre) tem
  /// prioridade sobre MODELO (selecionado do catálogo) quando os dois
  /// vierem preenchidos, mesma regra usada no sistema anterior.
  String get modeloExibido {
    if (outroModelo != null && outroModelo!.isNotEmpty) return outroModelo!;
    return modelo ?? '';
  }

  factory Equipamento.fromRow(Map<String, Object?> row) {
    return Equipamento(
      id: row['id'] as String,
      idAmbiente: row['id_ambiente'] as String,
      idLevantamento: row['id_levantamento'] as String,
      inep: row['inep'] as String,
      idCatalogo: row['id_catalogo'] as String?,
      tipoEquipamento: row['tipo_equipamento'] as String? ?? '',
      marca: row['marca'] as String?,
      modelo: row['modelo'] as String?,
      outroModelo: row['outro_modelo'] as String?,
      tombamento: row['tombamento'] as String?,
      numSerie: row['num_serie'] as String?,
      estado: row['estado'] as String?,
      criadoPor: row['criado_por'] as String?,
      fotoEtiquetaUrl: row['foto_etiqueta_url'] as String?,
      fotoEquipamentoUrl: row['foto_equipamento_url'] as String?,
      fotoEtiquetaLocalPath: row['foto_etiqueta_local_path'] as String?,
      fotoEquipamentoLocalPath: row['foto_equipamento_local_path'] as String?,
    );
  }
}

class EquipamentoInservivel {
  final String id;
  final String idAmbiente;
  final String idLevantamento;
  final String inep;
  final String tipoEquipamento;
  final String? marca;
  final String? modelo;
  final int quantidade;
  final String? criadoPor;

  const EquipamentoInservivel({
    required this.id,
    required this.idAmbiente,
    required this.idLevantamento,
    required this.inep,
    required this.tipoEquipamento,
    this.marca,
    this.modelo,
    required this.quantidade,
    this.criadoPor,
  });

  factory EquipamentoInservivel.fromRow(Map<String, Object?> row) {
    return EquipamentoInservivel(
      id: row['id'] as String,
      idAmbiente: row['id_ambiente'] as String,
      idLevantamento: row['id_levantamento'] as String,
      inep: row['inep'] as String,
      tipoEquipamento: row['tipo_equipamento'] as String? ?? '',
      marca: row['marca'] as String?,
      modelo: row['modelo'] as String?,
      quantidade: (row['quantidade'] as int?) ?? 1,
      criadoPor: row['criado_por'] as String?,
    );
  }
}

/// Alerta local de possível duplicidade — nunca bloqueia (mesma filosofia
/// não-bloqueante do `checarDuplicidade()` no backend, ver
/// claude/backend_levantamento.gs): só avisa, quem decide se salva mesmo
/// assim é o técnico.
class DuplicidadeEncontrada {
  final String tipo; // 'TOMBAMENTO' | 'NUM_SERIE'
  final String valor;
  const DuplicidadeEncontrada({required this.tipo, required this.valor});
}

/// EQUIPAMENTOS e EQUIPAMENTOS_INSERVIVEIS (§4/§5 Telas 5/6 do spec) —
/// dentro de um AMBIENTE. O motor de sincronização (push/pull) pra essas
/// duas tabelas já existia pronto (`LevantamentoSyncService`), construído
/// numa etapa anterior junto com o resto do sync transacional — esse
/// repositório cobre só a parte local (CRUD em campo + índice leve de
/// duplicidade).
class EquipamentosRepository {
  static const _uuid = Uuid();

  Future<List<Equipamento>> listarPorAmbiente(String idAmbiente) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'equipamentos',
      where: 'id_ambiente = ?',
      whereArgs: [idAmbiente],
      orderBy: 'criado_em ASC',
    );
    return rows.map(Equipamento.fromRow).toList();
  }

  Future<List<EquipamentoInservivel>> listarInserviveisPorAmbiente(String idAmbiente) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'equipamentos_inserviveis',
      where: 'id_ambiente = ?',
      whereArgs: [idAmbiente],
      orderBy: 'criado_em ASC',
    );
    return rows.map(EquipamentoInservivel.fromRow).toList();
  }

  Future<Equipamento?> buscar(String id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('equipamentos', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Equipamento.fromRow(rows.first);
  }

  // -- Duplicidade (índice local) ------------------------------------------

  String _chaveIndice(String tipo, String valor) => '$tipo|${valor.trim().toUpperCase()}';

  /// Checa Tombamento e Nº de Série contra o índice local — chamada ao
  /// tentar salvar no formulário de Equipamento (Tela 6). Só um aviso:
  /// nunca impede salvar (mesma filosofia do servidor — ver
  /// `checarDuplicidade()` no backend). `ignorarId` evita o item se
  /// comparar consigo mesmo ao editar.
  Future<List<DuplicidadeEncontrada>> verificarDuplicidade({
    String? tombamento,
    String? numSerie,
    String? ignorarId,
  }) async {
    final db = await AppDatabase.instance.database;
    final achados = <DuplicidadeEncontrada>[];

    Future<void> checar(String tipo, String? valor) async {
      final texto = valor?.trim() ?? '';
      if (texto.isEmpty) return;
      final chave = _chaveIndice(tipo, texto);
      final rows = await db.query('indice_duplicidade', where: 'chave = ?', whereArgs: [chave], limit: 1);
      if (rows.isEmpty) return;
      final idEncontrado = rows.first['id_equipamento'] as String?;
      if (idEncontrado != null && idEncontrado == ignorarId) return; // é o próprio registro sendo editado
      achados.add(DuplicidadeEncontrada(tipo: tipo, valor: texto));
    }

    await checar('TOMBAMENTO', tombamento);
    await checar('NUM_SERIE', numSerie);
    return achados;
  }

  Future<void> _atualizarIndice({
    required String idEquipamento,
    String? tombamentoAntigo,
    String? numSerieAntigo,
    String? tombamentoNovo,
    String? numSerieNovo,
  }) async {
    final db = await AppDatabase.instance.database;

    Future<void> remover(String tipo, String? valor) async {
      final texto = valor?.trim() ?? '';
      if (texto.isEmpty) return;
      await db.delete('indice_duplicidade', where: 'chave = ?', whereArgs: [_chaveIndice(tipo, texto)]);
    }

    Future<void> inserir(String tipo, String? valor) async {
      final texto = valor?.trim() ?? '';
      if (texto.isEmpty) return;
      await db.insert(
        'indice_duplicidade',
        {'chave': _chaveIndice(tipo, texto), 'tipo': tipo, 'id_equipamento': idEquipamento},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    // Só mexe na chave se o valor realmente mudou — evita apagar/recriar à
    // toa quando o resto do formulário é editado sem tocar em
    // tombamento/série.
    if (tombamentoAntigo != tombamentoNovo) {
      await remover('TOMBAMENTO', tombamentoAntigo);
      await inserir('TOMBAMENTO', tombamentoNovo);
    }
    if (numSerieAntigo != numSerieNovo) {
      await remover('NUM_SERIE', numSerieAntigo);
      await inserir('NUM_SERIE', numSerieNovo);
    }
  }

  // -- Equipamento ------------------------------------------------------

  /// Cria (`id` nulo) ou atualiza (`id` preenchido) um equipamento.
  /// ID_CATALOGO e CHAVE_MODELO nunca são calculados aqui — o servidor
  /// recalcula os dois a cada push (`processarCatalogo()` em
  /// claude/backend_levantamento.gs); localmente ficam nulos até o
  /// primeiro sync trazer de volta.
  Future<String> salvar({
    String? id,
    required String idAmbiente,
    required String idLevantamento,
    required String inep,
    required String tipoEquipamento,
    String? marca,
    String? modelo,
    String? outroModelo,
    String? tombamento,
    String? numSerie,
    String? estado,
    String? fotoEtiquetaLocalPath,
    String? fotoEquipamentoLocalPath,
    required String matricula,
    String? nomeTecnico,
  }) async {
    final db = await AppDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();
    final idFinal = id ?? _uuid.v4();
    final ehNovo = id == null;

    String? tombamentoAntigo;
    String? numSerieAntigo;

    if (id != null) {
      final existente = await buscar(id);
      tombamentoAntigo = existente?.tombamento;
      numSerieAntigo = existente?.numSerie;
      await db.update(
        'equipamentos',
        {
          'tipo_equipamento': tipoEquipamento,
          'marca': marca,
          'modelo': modelo,
          'outro_modelo': outroModelo,
          'tombamento': tombamento,
          'num_serie': numSerie,
          'estado': estado,
          // Só a foto LOCAL é gravada aqui — a URL remota é escrita à parte
          // por FotoUploadService depois do upload (ver comentário no
          // model Equipamento). Passar null aqui simplesmente mantém "sem
          // foto local ainda", nunca apaga uma URL já enviada.
          'foto_etiqueta_local_path': fotoEtiquetaLocalPath,
          'foto_equipamento_local_path': fotoEquipamentoLocalPath,
          'atualizado_em': agora,
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      await db.insert('equipamentos', {
        'id': idFinal,
        'id_ambiente': idAmbiente,
        'id_levantamento': idLevantamento,
        'inep': inep,
        'tipo_equipamento': tipoEquipamento,
        'marca': marca,
        'modelo': modelo,
        'outro_modelo': outroModelo,
        'tombamento': tombamento,
        'num_serie': numSerie,
        'estado': estado,
        'foto_etiqueta_local_path': fotoEtiquetaLocalPath,
        'foto_equipamento_local_path': fotoEquipamentoLocalPath,
        'criado_por': matricula,
        'criado_em': agora,
        'atualizado_em': agora,
        'sync_status': 'pending',
      });
    }

    await _atualizarIndice(
      idEquipamento: idFinal,
      tombamentoAntigo: tombamentoAntigo,
      numSerieAntigo: numSerieAntigo,
      tombamentoNovo: tombamento,
      numSerieNovo: numSerie,
    );

    if (ehNovo) {
      final descricaoModelo = (outroModelo != null && outroModelo.isNotEmpty) ? outroModelo : modelo;
      await AtividadesRepository().registrar(
        idLevantamento: idLevantamento,
        inep: inep,
        matricula: matricula,
        nomeTecnico: nomeTecnico,
        tipoEntidade: 'Equipamento',
        acao: AtividadesRepository.acaoAdicionado,
        descricao: [tipoEquipamento, marca, descricaoModelo].where((s) => s != null && s.isNotEmpty).join(' - '),
      );
    }

    return idFinal;
  }

  /// Duplica um equipamento já cadastrado — atalho pra quando o mesmo
  /// modelo se repete várias vezes no mesmo ambiente (ex.: vários desktops
  /// iguais). Copia tudo MENOS Tombamento e Nº de Série (são únicos por
  /// definição — duplicar os dois criaria uma falsa duplicidade na hora),
  /// deixando os dois em branco pro técnico completar no equipamento novo.
  Future<String> duplicar(String idOrigem, {required String matricula}) async {
    final origem = await buscar(idOrigem);
    if (origem == null) {
      throw StateError('Equipamento de origem não encontrado ($idOrigem).');
    }
    return salvar(
      idAmbiente: origem.idAmbiente,
      idLevantamento: origem.idLevantamento,
      inep: origem.inep,
      tipoEquipamento: origem.tipoEquipamento,
      marca: origem.marca,
      modelo: origem.modelo,
      outroModelo: origem.outroModelo,
      estado: origem.estado,
      matricula: matricula,
      // tombamento/numSerie ficam de fora de propósito — ver doc acima.
    );
  }

  /// Remove um equipamento — só local. O backend nunca deleta linha
  /// nenhuma (`upsertRows` só adiciona/atualiza — ver
  /// LevantamentoSyncService), então se esse equipamento já tinha sido
  /// sincronizado antes, ele continua existindo na planilha e pode voltar
  /// num próximo pull. Avisar isso na tela antes de confirmar.
  Future<void> remover(String id, {required String matricula, String? nomeTecnico}) async {
    final equipamento = await buscar(id);
    final db = await AppDatabase.instance.database;
    await db.delete('equipamentos', where: 'id = ?', whereArgs: [id]);
    if (equipamento != null) {
      await _atualizarIndice(
        idEquipamento: id,
        tombamentoAntigo: equipamento.tombamento,
        numSerieAntigo: equipamento.numSerie,
        tombamentoNovo: null,
        numSerieNovo: null,
      );
      // Tombstone (2026-09-14) — ver RemocoesPendentesRepository: sem isto,
      // um equipamento já sincronizado voltava no próximo pull.
      await RemocoesPendentesRepository().registrar(
        tabela: 'equipamentos',
        idRegistro: id,
        idLevantamento: equipamento.idLevantamento,
      );
      await AtividadesRepository().registrar(
        idLevantamento: equipamento.idLevantamento,
        inep: equipamento.inep,
        matricula: matricula,
        nomeTecnico: nomeTecnico,
        tipoEntidade: 'Equipamento',
        acao: AtividadesRepository.acaoRemovido,
        descricao: [equipamento.tipoEquipamento, equipamento.marca, equipamento.modeloExibido]
            .where((s) => s != null && s.isNotEmpty)
            .join(' - '),
      );
    }
  }

  // -- Inservível ---------------------------------------------------------

  Future<String> salvarInservivel({
    String? id,
    required String idAmbiente,
    required String idLevantamento,
    required String inep,
    required String tipoEquipamento,
    String? marca,
    String? modelo,
    required int quantidade,
    required String matricula,
    String? nomeTecnico,
  }) async {
    final db = await AppDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();
    final idFinal = id ?? _uuid.v4();
    final ehNovo = id == null;
    if (id != null) {
      await db.update(
        'equipamentos_inserviveis',
        {
          'tipo_equipamento': tipoEquipamento,
          'marca': marca,
          'modelo': modelo,
          'quantidade': quantidade,
          'atualizado_em': agora,
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      await db.insert('equipamentos_inserviveis', {
        'id': idFinal,
        'id_ambiente': idAmbiente,
        'id_levantamento': idLevantamento,
        'inep': inep,
        'tipo_equipamento': tipoEquipamento,
        'marca': marca,
        'modelo': modelo,
        'quantidade': quantidade,
        'criado_por': matricula,
        'criado_em': agora,
        'atualizado_em': agora,
        'sync_status': 'pending',
      });
    }
    if (ehNovo) {
      await AtividadesRepository().registrar(
        idLevantamento: idLevantamento,
        inep: inep,
        matricula: matricula,
        nomeTecnico: nomeTecnico,
        tipoEntidade: 'Inservível',
        acao: AtividadesRepository.acaoAdicionado,
        descricao: '$tipoEquipamento${marca != null && marca.isNotEmpty ? " - $marca" : ""} (x$quantidade)',
      );
    }
    return idFinal;
  }

  /// Só local — mesmo caveat do `remover` de equipamento acima.
  Future<void> removerInservivel(String id, {required String matricula, String? nomeTecnico}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('equipamentos_inserviveis', where: 'id = ?', whereArgs: [id], limit: 1);
    await db.delete('equipamentos_inserviveis', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      final inservivel = EquipamentoInservivel.fromRow(rows.first);
      // Tombstone (2026-09-14) — ver RemocoesPendentesRepository.
      await RemocoesPendentesRepository().registrar(
        tabela: 'equipamentos_inserviveis',
        idRegistro: id,
        idLevantamento: inservivel.idLevantamento,
      );
      await AtividadesRepository().registrar(
        idLevantamento: inservivel.idLevantamento,
        inep: inservivel.inep,
        matricula: matricula,
        nomeTecnico: nomeTecnico,
        tipoEntidade: 'Inservível',
        acao: AtividadesRepository.acaoRemovido,
        descricao:
            '${inservivel.tipoEquipamento}${inservivel.marca != null && inservivel.marca!.isNotEmpty ? " - ${inservivel.marca}" : ""} (x${inservivel.quantidade})',
      );
    }
  }
}
