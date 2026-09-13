import '../remote/api_client.dart';
import '../remote/auth_service.dart';
import 'database.dart';

class ServidorAssinante {
  final String matricula;
  final String nome;
  const ServidorAssinante({required this.matricula, required this.nome});

  factory ServidorAssinante.fromRow(Map<String, Object?> row) {
    return ServidorAssinante(
      matricula: row['matricula'] as String,
      nome: row['nome'] as String? ?? row['matricula'] as String,
    );
  }

  factory ServidorAssinante.fromRemoto(Map<String, dynamic> json) {
    return ServidorAssinante(
      matricula: json['MATRICULA']?.toString() ?? '',
      nome: json['NOME']?.toString() ?? json['MATRICULA']?.toString() ?? '',
    );
  }
}

/// Servidor com login habilitado no app (técnico ou ADM) — usado pela tela
/// "Gerenciar técnicos" (2026-09-13) pra ADM achar quem precisa de reset de
/// senha. Diferente de [ServidorAssinante] (que é sobre PODE_ASSINAR, sem
/// nenhuma relação com login/senha).
class ServidorComLogin {
  final String matricula;
  final String nome;
  final String papel;
  const ServidorComLogin({required this.matricula, required this.nome, required this.papel});

  factory ServidorComLogin.fromRow(Map<String, Object?> row) {
    return ServidorComLogin(
      matricula: row['matricula'] as String,
      nome: row['nome'] as String? ?? row['matricula'] as String,
      papel: row['papel'] as String? ?? 'TECNICO',
    );
  }
}

/// SERVIDORES é referência (populada em `pull_referencia`, ~26-29 mil
/// linhas — ver §10 do spec). Desde 2026-09-12 a aba INTEIRA chega no
/// aparelho a cada sync (ver `actionPullReferencia` no backend) — não só
/// quem tem `LOGIN_HABILITADO`/`PODE_ASSINAR` como antes — pra Tela 8 poder
/// escolher qualquer responsável 100% offline. [buscarRemoto] continua
/// existindo só como fallback, pro caso raro de alguém cadastrado depois do
/// último sync deste aparelho.
class ServidoresRepository {
  ServidoresRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();
  final ApiClient _api;

  /// Mantido por compatibilidade — lista só quem tem `PODE_ASSINAR=true`.
  /// A Tela 8 (Conclusão) não usa mais isso pra restringir a escolha (ver
  /// [buscarLocal]); o backend continua conferindo essa mesma regra de novo
  /// (redundante de propósito) em `actionPushLevantamento`.
  Future<List<ServidorAssinante>> listarAssinantes() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'servidores',
      where: 'pode_assinar = 1',
      orderBy: 'nome ASC',
    );
    return rows.map(ServidorAssinante.fromRow).toList();
  }

  /// Busca livre por matrícula OU nome — não só quem tem `PODE_ASSINAR=true`
  /// (decisão de 2026-09-12: a Tela 8/Conclusão deixou de restringir a
  /// escolha do responsável pela assinatura só a quem já tinha essa
  /// permissão marcada; a validação de verdade continua sendo do backend).
  /// Funciona 100% offline e, desde que `pull_referencia` passou a baixar
  /// SERVIDORES inteiro (ver comentário da classe), alcança praticamente
  /// qualquer servidor sem precisar de internet — [buscarRemoto] cobre só o
  /// caso raro de alguém cadastrado depois do último sync deste aparelho. A
  /// tabela local pode ter dezenas de milhares de linhas agora, então a
  /// busca sempre limita o resultado (nunca devolve a tabela toda pra UI —
  /// mesmo raciocínio do `CatalogoRepository.buscar`).
  Future<List<ServidorAssinante>> buscarLocal(String query) async {
    final db = await AppDatabase.instance.database;
    final termo = query.trim();
    if (termo.isEmpty) {
      final rows = await db.query('servidores', orderBy: 'nome ASC', limit: 30);
      return rows.map(ServidorAssinante.fromRow).toList();
    }
    final like = '%$termo%';
    final rows = await db.query(
      'servidores',
      where: 'matricula LIKE ? OR nome LIKE ?',
      whereArgs: [like, like],
      orderBy: 'nome ASC',
      limit: 20,
    );
    return rows.map(ServidorAssinante.fromRow).toList();
  }

  /// Busca ao vivo por matrícula ou nome em TODA a aba SERVIDORES no
  /// backend (26-29 mil linhas) — não só no subconjunto já sincronizado
  /// neste aparelho (ver [buscarLocal]). AÇÃO ONLINE-ONLY (igual
  /// `criarModelo`/`login`): exige internet, e é chamada só como
  /// complemento da busca local — quando a pessoa não acha o responsável
  /// entre quem já está no aparelho. Lança [ApiException] se não tiver rede
  /// ou o servidor recusar; quem chama decide o que mostrar (ver
  /// `servidor_picker_sheet.dart`).
  Future<List<ServidorAssinante>> buscarRemoto({
    required String query,
    required Session session,
  }) async {
    final termo = query.trim();
    if (termo.length < 2) return const [];
    final resposta = await _api.call('buscar_servidor', {
      'token': session.token,
      'termo': termo,
    });
    if (resposta['ok'] != true) {
      throw ApiException(resposta['error']?.toString() ?? 'Não foi possível buscar servidores.');
    }
    final lista = (resposta['servidores'] as List? ?? const [])
        .cast<Map>()
        .map((m) => ServidorAssinante.fromRemoto(m.cast<String, dynamic>()))
        .toList();
    return lista;
  }

  /// Lista, 100% offline, todo servidor com LOGIN_HABILITADO=true (quem usa
  /// o app de verdade — técnicos e ADMs) — usada pela tela "Gerenciar
  /// técnicos" (2026-09-13) pra ADM achar quem precisa de reset de senha.
  /// Não inclui quem só PODE_ASSINAR (diretores/responsáveis sem login).
  Future<List<ServidorComLogin>> listarComLogin() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'servidores',
      where: 'login_habilitado = 1',
      orderBy: 'nome ASC',
    );
    return rows.map(ServidorComLogin.fromRow).toList();
  }

  /// Reseta a senha de outro servidor pra "123456", já marcada como
  /// temporária no servidor (SENHA_TEMPORARIA=true) — a próxima vez que
  /// essa pessoa logar, o app força a troca antes de deixar entrar (ver
  /// TrocarSenhaScreen/LoginScreen). AÇÃO ONLINE-ONLY, só ADM (o backend
  /// confere de novo — nunca confia só na tela ter escondido o botão pra
  /// quem não é ADM). Não mexe em nada local: SERVIDORES local nunca guarda
  /// hash/senha (ver ServidoresRepository/actionPullReferencia), então não
  /// há nada pra atualizar aqui além do próprio backend.
  Future<void> resetarSenha({required String matricula, required Session session}) async {
    final resposta = await _api.call('resetar_senha', {
      'token': session.token,
      'matricula': matricula,
    });
    if (resposta['ok'] != true) {
      throw ApiException(resposta['error']?.toString() ?? 'Não foi possível resetar a senha.');
    }
  }
}
