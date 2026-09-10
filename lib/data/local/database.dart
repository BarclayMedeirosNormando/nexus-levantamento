import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:sqflite/sqflite.dart';

/// Banco local (SQLite via sqflite) — é o que faz o app funcionar offline.
///
/// Duas famílias de tabela, espelhando exatamente as abas do backend (ver
/// SHEET_HEADERS em claude/backend_levantamento.gs e §12 do spec):
///
/// - Tabelas de REFERÊNCIA (escolas, servidores, contratos_internet,
///   ambientes_padrao): só leitura no app, recebidas inteiras a cada
///   `pull_referencia` e substituídas localmente (REPLACE INTO) — nunca são
///   editadas no aparelho.
/// - Tabelas TRANSACIONAIS (levantamentos, ambientes, equipamentos, etc.):
///   criadas/editadas em campo, com uma coluna extra só local
///   `sync_status` ('pending' | 'synced') pra saber o que ainda falta
///   mandar pro servidor. Isso não existe no Sheets — é controle interno
///   do app.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'nexus_levantamento.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    // Em Android/iOS, `getDatabasesPath()` (do próprio sqflite) já aponta pra
    // um diretório de app estável. Em desktop (Windows/Linux/macOS), rodando
    // via `databaseFactoryFfi`, esse mesmo `getDatabasesPath()` não tem uma
    // localização fixa garantida — pode variar conforme o diretório de
    // trabalho de onde o executável foi lançado (`flutter run` vs abrir o
    // .exe direto em build\windows\...\Debug\, por exemplo), o que faz
    // parecer que o banco "some" ao reabrir o app de outro jeito, quando na
    // verdade ele foi criado num lugar diferente a cada vez.
    //
    // Por isso usamos `path_provider` (que já é dependência do projeto) pra
    // pegar o diretório de dados do app de verdade — esse é sempre o mesmo
    // caminho absoluto (ex.: %APPDATA%\<app> no Windows), não importa como
    // o executável foi iniciado.
    final supportDir = await path_provider.getApplicationSupportDirectory();
    final path = join(supportDir.path, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    final batch = db.batch();

    // ---------------------------------------------------------------------
    // Tabelas de referência — somente leitura, substituídas a cada sync.
    // ---------------------------------------------------------------------
    batch.execute('''
      CREATE TABLE escolas (
        inep TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        municipio TEXT,
        regional TEXT,
        endereco TEXT,
        latitude TEXT,
        longitude TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE servidores (
        matricula TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        pode_assinar INTEGER NOT NULL DEFAULT 0,
        login_habilitado INTEGER NOT NULL DEFAULT 0,
        papel TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE contratos_internet (
        id_contrato TEXT PRIMARY KEY,
        inep TEXT NOT NULL,
        operadora TEXT,
        plano TEXT,
        velocidade_contratada_mbps TEXT
      )
    ''');
    batch.execute('CREATE INDEX idx_contratos_inep ON contratos_internet(inep)');

    batch.execute('''
      CREATE TABLE ambientes_padrao (
        id_tipo_ambiente TEXT PRIMARY KEY,
        nome_padrao TEXT NOT NULL,
        obrigatorio INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ---------------------------------------------------------------------
    // Tabelas transacionais — criadas/editadas em campo. sync_status é
    // controle local: 'pending' até confirmar que o servidor recebeu.
    // ---------------------------------------------------------------------
    batch.execute('''
      CREATE TABLE levantamentos (
        id TEXT PRIMARY KEY,
        inep TEXT NOT NULL,
        tecnico_abertura TEXT,
        data_inicio TEXT,
        lat_abertura REAL,
        long_abertura REAL,
        status TEXT NOT NULL DEFAULT 'em_andamento',
        id_servidor_responsavel TEXT,
        data_assinatura TEXT,
        assinatura_url TEXT,
        reaberto_por TEXT,
        data_reabertura TEXT,
        criado_em TEXT,
        atualizado_em TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    batch.execute('CREATE INDEX idx_levantamentos_inep ON levantamentos(inep)');
    batch.execute('CREATE INDEX idx_levantamentos_sync ON levantamentos(sync_status)');

    batch.execute('''
      CREATE TABLE levantamento_tecnicos (
        id_levantamento TEXT NOT NULL,
        matricula_tecnico TEXT NOT NULL,
        adicionado_em TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        PRIMARY KEY (id_levantamento, matricula_tecnico)
      )
    ''');

    batch.execute('''
      CREATE TABLE ambientes (
        id TEXT PRIMARY KEY,
        id_levantamento TEXT NOT NULL,
        inep TEXT NOT NULL,
        id_tipo_ambiente TEXT,
        nome_ambiente TEXT,
        origem TEXT,
        criado_por TEXT,
        criado_em TEXT,
        atualizado_em TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    batch.execute('CREATE INDEX idx_ambientes_levantamento ON ambientes(id_levantamento)');

    batch.execute('''
      CREATE TABLE equipamentos (
        id TEXT PRIMARY KEY,
        id_ambiente TEXT NOT NULL,
        id_levantamento TEXT NOT NULL,
        inep TEXT NOT NULL,
        id_catalogo TEXT,
        tipo_equipamento TEXT,
        marca TEXT,
        modelo TEXT,
        outro_modelo TEXT,
        tombamento TEXT,
        num_serie TEXT,
        foto_etiqueta_url TEXT,
        foto_equipamento_url TEXT,
        estado TEXT,
        chave_modelo TEXT,
        criado_por TEXT,
        criado_em TEXT,
        atualizado_em TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    batch.execute('CREATE INDEX idx_equipamentos_ambiente ON equipamentos(id_ambiente)');
    batch.execute('CREATE INDEX idx_equipamentos_levantamento ON equipamentos(id_levantamento)');

    batch.execute('''
      CREATE TABLE equipamentos_inserviveis (
        id TEXT PRIMARY KEY,
        id_ambiente TEXT NOT NULL,
        id_levantamento TEXT NOT NULL,
        inep TEXT NOT NULL,
        tipo_equipamento TEXT,
        marca TEXT,
        modelo TEXT,
        quantidade INTEGER,
        criado_por TEXT,
        criado_em TEXT,
        atualizado_em TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    batch.execute('''
      CREATE TABLE catalogo_equipamentos (
        id_catalogo TEXT PRIMARY KEY,
        tipo_equipamento TEXT,
        marca TEXT,
        modelo TEXT,
        chave_modelo TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE conectividade (
        id TEXT PRIMARY KEY,
        id_levantamento TEXT NOT NULL,
        inep TEXT NOT NULL,
        tipo_pagamento TEXT,
        id_contrato TEXT,
        operadora TEXT,
        velocidade_contratada_mbps TEXT,
        velocidade_medida_download_mbps REAL,
        velocidade_medida_upload_mbps REAL,
        status_link TEXT,
        id_ambiente TEXT,
        criado_por TEXT,
        criado_em TEXT,
        atualizado_em TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    batch.execute('''
      CREATE TABLE wifi (
        id TEXT PRIMARY KEY,
        id_levantamento TEXT NOT NULL,
        inep TEXT NOT NULL,
        ssid TEXT,
        senha TEXT,
        criado_por TEXT,
        criado_em TEXT,
        atualizado_em TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    // ---------------------------------------------------------------------
    // Índice leve de duplicidade (tombamento/série) — checagem instantânea
    // em campo, sem esperar o servidor. Ver spec §5b/§10: é só um alerta
    // local, a checagem que vale de verdade é sempre a do servidor no
    // push_levantamento.
    // ---------------------------------------------------------------------
    batch.execute('''
      CREATE TABLE indice_duplicidade (
        chave TEXT PRIMARY KEY,
        tipo TEXT NOT NULL,
        id_equipamento TEXT NOT NULL
      )
    ''');

    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
