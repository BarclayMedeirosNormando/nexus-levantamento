import 'package:sqflite/sqflite.dart';
import '../remote/api_client.dart';
import '../remote/auth_service.dart';
import 'database.dart';

class CatalogoItem {
  final String idCatalogo;
  final String tipoEquipamento;
  final String? marca;
  final String? modelo;

  const CatalogoItem({
    required this.idCatalogo,
    required this.tipoEquipamento,
    this.marca,
    this.modelo,
  });

  String get label {
    final partes = [
      tipoEquipamento,
      if (marca != null && marca!.isNotEmpty) marca,
      if (modelo != null && modelo!.isNotEmpty) modelo,
    ];
    return partes.join(' · ');
  }

  factory CatalogoItem.fromRow(Map<String, Object?> row) {
    return CatalogoItem(
      idCatalogo: row['id_catalogo'] as String,
      tipoEquipamento: row['tipo_equipamento'] as String? ?? '',
      marca: row['marca'] as String?,
      modelo: row['modelo'] as String?,
    );
  }
}

/// CATALOGO_EQUIPAMENTOS — tabela de referência, populada a cada
/// `pull_referencia` (ver SyncService), acumulada automaticamente pelo
/// servidor (`processarCatalogo()` em claude/backend_levantamento.gs) a
/// partir de todo TIPO_EQUIPAMENTO+MARCA+MODELO já digitado por qualquer
/// técnico em qualquer push. Serve pra autocompletar o formulário de
/// Equipamento/Inservível (Telas 5/6) com o que já foi visto antes,
/// reduzindo digitação repetida.
///
/// Desde a tela "Catálogo de Modelos" (pré-cadastro de modelos antes de ir a
/// campo), esta tabela também recebe gravação direta do app através de
/// [criarModelo] — a única exceção ao "só leitura, só o servidor escreve"
/// de antes. É uma ação online-only (igual login), então continua sendo o
/// servidor quem decide o ID_CATALOGO/CHAVE_MODELO definitivos; o app só
/// espelha localmente o resultado pra não esperar o próximo sync.
class CatalogoRepository {
  CatalogoRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();
  final ApiClient _api;

  // Listas herdadas do sistema AppSheet anterior (ver
  // claude/dashboard_auditoria.html) — mantidas pra dar continuidade às
  // categorias já usadas nos dashboards existentes. São só sugestões
  // (chips de atalho); o campo sempre aceita texto livre também, nada aqui
  // bloqueia digitar algo fora da lista.
  static const tiposSugeridos = [
    'Desktop',
    'Notebook',
    'Tablet',
    'Impressora',
    'Projetor',
    'Switch',
    'Roteador',
    'Access Point',
    'Monitor',
    'Tv',
    'Rack',
    'Estabilizador',
    'Outro',
  ];

  static const marcasSugeridas = [
    'Daten',
    'HP',
    'ZMAX',
    'Dell',
    'Cisco',
    'Positivo',
    'Multilaser',
    'Dlink',
    'TpLink',
    'Epson',
    'Samsung',
    'Ricoh',
    'Lg',
    'Intelbrás',
    'Outro',
  ];

  static const estadosEquipamento = ['Bom', 'Regular', 'Ruim', 'Inoperante'];

  /// Busca livre no catálogo já sincronizado — usada pra "puxar" um
  /// equipamento repetido (mesmo tipo/marca/modelo já visto em outro
  /// ambiente/escola) sem redigitar tudo. Prefixo/trecho em qualquer um dos
  /// três campos, no máximo 20-30 resultados (evita carregar o catálogo
  /// inteiro numa escola grande direto na tela — ver aviso de performance
  /// do spec sobre SELECT/FILTER pesado, mesmo raciocínio aqui: nunca
  /// devolver a tabela toda pra UI).
  Future<List<CatalogoItem>> buscar(String query) async {
    final db = await AppDatabase.instance.database;
    final termo = query.trim();
    if (termo.isEmpty) {
      final rows = await db.query(
        'catalogo_equipamentos',
        orderBy: 'tipo_equipamento ASC',
        limit: 30,
      );
      return rows.map(CatalogoItem.fromRow).toList();
    }
    final like = '%$termo%';
    final rows = await db.query(
      'catalogo_equipamentos',
      where: 'tipo_equipamento LIKE ? OR marca LIKE ? OR modelo LIKE ?',
      whereArgs: [like, like, like],
      orderBy: 'tipo_equipamento ASC',
      limit: 20,
    );
    return rows.map(CatalogoItem.fromRow).toList();
  }

  /// Registra um modelo direto no catálogo central — usado pela tela
  /// "Catálogo de Modelos" e pelo botão "Criar modelo" da busca de catálogo
  /// no formulário de Equipamento, quando a busca não encontra nada.
  ///
  /// AÇÃO ONLINE-ONLY (igual `login`): não passa pela fila de sincronização
  /// offline — exige internet na hora, porque o pedido era sincronizar de
  /// verdade entre aparelhos assim que o modelo é criado, não só quando o
  /// primeiro equipamento que usa esse modelo for sincronizado depois.
  /// Lança [ApiException] se não tiver rede ou o servidor recusar; quem
  /// chama decide o que mostrar (ver ModeloFormScreen). Continuar digitando
  /// Tipo/Marca/Modelo direto no formulário, sem passar por aqui, continua
  /// funcionando 100% offline — esse caminho alimenta o catálogo sozinho,
  /// do lado do servidor, no próximo push_levantamento (processarCatalogo).
  ///
  /// Dedup por CHAVE_MODELO já é feita no servidor: criar de novo um combo
  /// que já existe nunca duplica linha lá, só devolve o item existente.
  Future<CatalogoItem> criarModelo({
    required Session session,
    required String tipoEquipamento,
    required String marca,
    required String modelo,
  }) async {
    final resposta = await _api.call('criar_modelo_catalogo', {
      'token': session.token,
      'tipo_equipamento': tipoEquipamento,
      'marca': marca,
      'modelo': modelo,
    });

    if (resposta['ok'] != true) {
      throw ApiException(resposta['error']?.toString() ?? 'Não foi possível criar o modelo.');
    }

    final item = (resposta['item'] as Map).cast<String, dynamic>();
    final catalogoItem = CatalogoItem(
      idCatalogo: item['ID_CATALOGO']?.toString() ?? '',
      tipoEquipamento: item['TIPO_EQUIPAMENTO']?.toString() ?? tipoEquipamento,
      marca: item['MARCA']?.toString() ?? marca,
      modelo: item['MODELO']?.toString() ?? modelo,
    );

    // Espelha localmente na hora — pra já aparecer na busca deste aparelho
    // sem esperar o próximo "Sincronizar" manual (que é quando o
    // pull_referencia normalmente traria essa linha de volta).
    final db = await AppDatabase.instance.database;
    await db.insert(
      'catalogo_equipamentos',
      {
        'id_catalogo': catalogoItem.idCatalogo,
        'tipo_equipamento': catalogoItem.tipoEquipamento,
        'marca': catalogoItem.marca,
        'modelo': catalogoItem.modelo,
        'chave_modelo': item['CHAVE_MODELO']?.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return catalogoItem;
  }

  /// Edita um modelo já existente no catálogo (corrigir um erro de
  /// digitação, por exemplo) — mesma ação online-only de [criarModelo],
  /// agora chamando `atualizar_modelo_catalogo` no backend. O servidor
  /// recusa se a nova combinação de Tipo/Marca/Modelo já pertencer a OUTRO
  /// modelo (a checagem de duplicidade lança [ApiException] com a
  /// mensagem do servidor, igual qualquer outro erro de negócio aqui).
  ///
  /// Decisão do usuário (2026-09-11): editar aqui também propaga pro
  /// Tipo/Marca/Modelo de todo equipamento JÁ cadastrado que usa esse
  /// modelo (`ID_CATALOGO`) — o servidor faz essa propagação sozinho (ver
  /// propagarEdicaoModeloParaEquipamentos no backend) e devolve quantas
  /// linhas mudaram em `equipamentos_atualizados`; o app só repassa esse
  /// número pra UI mostrar (ver ModeloFormScreen/CatalogoModelosScreen).
  /// Só afeta a cópia local dos equipamentos no próximo sync (o merge do
  /// LevantamentoSyncService já sobrescreve local com o que veio do
  /// servidor, exceto linha marcada `pending` — ver `_mergeLinhaSimples`) —
  /// esta função só espelha a linha do CATALOGO_EQUIPAMENTOS em si, igual
  /// [criarModelo] já fazia.
  Future<ModeloAtualizadoResultado> atualizarModelo({
    required Session session,
    required String idCatalogo,
    required String tipoEquipamento,
    required String marca,
    required String modelo,
  }) async {
    final resposta = await _api.call('atualizar_modelo_catalogo', {
      'token': session.token,
      'id_catalogo': idCatalogo,
      'tipo_equipamento': tipoEquipamento,
      'marca': marca,
      'modelo': modelo,
    });

    if (resposta['ok'] != true) {
      throw ApiException(resposta['error']?.toString() ?? 'Não foi possível salvar as alterações.');
    }

    final item = (resposta['item'] as Map).cast<String, dynamic>();
    final catalogoItem = CatalogoItem(
      idCatalogo: item['ID_CATALOGO']?.toString() ?? idCatalogo,
      tipoEquipamento: item['TIPO_EQUIPAMENTO']?.toString() ?? tipoEquipamento,
      marca: item['MARCA']?.toString() ?? marca,
      modelo: item['MODELO']?.toString() ?? modelo,
    );

    final db = await AppDatabase.instance.database;
    await db.insert(
      'catalogo_equipamentos',
      {
        'id_catalogo': catalogoItem.idCatalogo,
        'tipo_equipamento': catalogoItem.tipoEquipamento,
        'marca': catalogoItem.marca,
        'modelo': catalogoItem.modelo,
        'chave_modelo': item['CHAVE_MODELO']?.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final equipamentosAtualizados = (resposta['equipamentos_atualizados'] as num?)?.toInt() ?? 0;
    return ModeloAtualizadoResultado(item: catalogoItem, equipamentosAtualizados: equipamentosAtualizados);
  }
}

/// Resultado de [CatalogoRepository.atualizarModelo]: o [item] do catálogo
/// já salvo, e quantos equipamentos já cadastrados (mesmo ID_CATALOGO)
/// tiveram Tipo/Marca/Modelo propagados junto no servidor.
class ModeloAtualizadoResultado {
  const ModeloAtualizadoResultado({required this.item, required this.equipamentosAtualizados});
  final CatalogoItem item;
  final int equipamentosAtualizados;
}
