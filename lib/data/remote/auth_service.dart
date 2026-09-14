import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';

/// Sessão do usuário logado — o que o app precisa lembrar entre uma
/// abertura e outra (guardado no secure storage, não no SQLite normal,
/// porque carrega o token).
class Session {
  final String token;
  final String matricula;
  final String papel; // 'TECNICO' ou 'ADM'
  final String nome;
  final bool senhaTemporaria;

  const Session({
    required this.token,
    required this.matricula,
    required this.papel,
    required this.nome,
    this.senhaTemporaria = false,
  });

  bool get isAdm => papel == 'ADM';

  Session copyWith({bool? senhaTemporaria}) {
    return Session(
      token: token,
      matricula: matricula,
      papel: papel,
      nome: nome,
      senhaTemporaria: senhaTemporaria ?? this.senhaTemporaria,
    );
  }
}

/// Login é a ÚNICA ação que exige internet na hora (ver design do backend:
/// token HMAC sem expiração, feito pra o app trabalhar offline por dias
/// depois do primeiro login). Esta classe guarda a sessão localmente e
/// resolve o login contra o servidor.
class AuthService {
  AuthService({ApiClient? apiClient, FlutterSecureStorage? storage})
      : _api = apiClient ?? ApiClient(),
        _storage = storage ?? const FlutterSecureStorage();

  final ApiClient _api;
  final FlutterSecureStorage _storage;

  static const _kToken = 'session_token';
  static const _kMatricula = 'session_matricula';
  static const _kPapel = 'session_papel';
  static const _kNome = 'session_nome';
  // 2026-09-13: junto com o fluxo de troca de senha obrigatória — precisa
  // sobreviver a fechar/abrir o app porque o login (única ação que exige
  // rede) não roda de novo a cada abertura (ver getSavedSession/
  // _StartupGate em app.dart). Sem persistir isso aqui, alguém que
  // recebesse uma senha temporária/resetada e fechasse o app antes de
  // trocar escaparia da obrigação na próxima vez que abrisse (cairia
  // direto na Home via sessão salva).
  static const _kSenhaTemporaria = 'session_senha_temporaria';
  // 2026-09-14: hash SHA-256 da senha, salvo aqui SÓ pra confirmação local
  // de ações destrutivas (ver conferirSenhaLocal, usado em "Remover
  // ambiente") — nunca enviado a lugar nenhum, nunca usado pra autenticar
  // contra o servidor (isso continua sendo só o token). Existe porque o
  // app é offline-first: pedir senha de novo pra confirmar algo em campo
  // não pode depender de internet no momento (diferente de
  // reabrir_levantamento, que reautentica no servidor de propósito, por
  // ser uma ação rara e sempre feita por ADM).
  static const _kSenhaHashLocal = 'session_senha_hash_local';

  /// Faz login contra o servidor. Lança [ApiException] se não tiver rede;
  /// retorna null (sem lançar) se o servidor respondeu mas recusou o login
  /// (matrícula/senha erradas, login desabilitado etc.) — a mensagem de
  /// erro do backend vai em [LoginResult.error] nesse caso.
  Future<LoginResult> login({required String matricula, required String senha}) async {
    final resposta = await _api.call('login', {
      'matricula': matricula.trim(),
      'senha': senha,
    });

    if (resposta['ok'] != true) {
      return LoginResult.failure(resposta['error']?.toString() ?? 'Não foi possível entrar.');
    }

    final session = Session(
      token: resposta['token'] as String,
      matricula: matricula.trim(),
      papel: (resposta['papel'] as String?)?.toUpperCase() ?? 'TECNICO',
      nome: resposta['nome']?.toString() ?? '',
      senhaTemporaria: resposta['senha_temporaria'] == true,
    );

    await _saveSession(session);
    await _salvarHashSenhaLocal(senha);
    return LoginResult.success(session);
  }

  Future<void> _saveSession(Session session) async {
    await _storage.write(key: _kToken, value: session.token);
    await _storage.write(key: _kMatricula, value: session.matricula);
    await _storage.write(key: _kPapel, value: session.papel);
    await _storage.write(key: _kNome, value: session.nome);
    await _storage.write(key: _kSenhaTemporaria, value: session.senhaTemporaria ? '1' : '0');
  }

  /// Lê a sessão salva (se houver) — usado na abertura do app pra decidir
  /// se pula direto pra Home ou pede login.
  Future<Session?> getSavedSession() async {
    final token = await _storage.read(key: _kToken);
    if (token == null) return null;
    return Session(
      token: token,
      matricula: await _storage.read(key: _kMatricula) ?? '',
      papel: await _storage.read(key: _kPapel) ?? 'TECNICO',
      nome: await _storage.read(key: _kNome) ?? '',
      senhaTemporaria: (await _storage.read(key: _kSenhaTemporaria)) == '1',
    );
  }

  /// Troca a senha do próprio usuário logado — chamado tanto no fluxo
  /// obrigatório (senha temporária/resetada, ver TrocarSenhaScreen) quanto
  /// no voluntário (Home → "Trocar minha senha"). Exige o token da sessão
  /// atual (requireAuth no backend) — não pede a senha antiga porque quem
  /// está chamando isso já provou identidade ao logar. Em caso de sucesso,
  /// atualiza a sessão salva localmente (senhaTemporaria vira false) e
  /// devolve a Session atualizada pra quem chamou trocar a que está usando
  /// em memória (ex: navegar pra Home com a session certa).
  Future<Session> trocarSenha({required Session session, required String novaSenha}) async {
    final resposta = await _api.call('trocar_senha', {
      'token': session.token,
      'nova_senha': novaSenha,
    });
    if (resposta['ok'] != true) {
      throw ApiException(resposta['error']?.toString() ?? 'Não foi possível trocar a senha.');
    }
    final atualizada = session.copyWith(senhaTemporaria: false);
    await _saveSession(atualizada);
    await _salvarHashSenhaLocal(novaSenha);
    return atualizada;
  }

  Future<void> _salvarHashSenhaLocal(String senha) async {
    final hash = sha256.convert(utf8.encode(senha)).toString();
    await _storage.write(key: _kSenhaHashLocal, value: hash);
  }

  /// Confere a senha digitada contra o hash local salvo no último
  /// login/troca de senha — usado pra confirmar ações destrutivas (ex.:
  /// remover ambiente) sem exigir internet no momento da confirmação.
  /// Sempre há um hash salvo depois de qualquer login bem-sucedido (ver
  /// login/_salvarHashSenhaLocal acima), então isso só falha se a sessão
  /// salva vier de antes desta mudança (nesse caso, pede pra a pessoa
  /// logar de novo pelo menos uma vez).
  Future<bool> conferirSenhaLocal(String senhaDigitada) async {
    final hashSalvo = await _storage.read(key: _kSenhaHashLocal);
    if (hashSalvo == null) return false;
    final hashDigitado = sha256.convert(utf8.encode(senhaDigitada)).toString();
    return hashDigitado == hashSalvo;
  }

  Future<void> logout() async {
    await _storage.deleteAll();
  }
}

class LoginResult {
  final bool ok;
  final Session? session;
  final String? error;

  LoginResult._({required this.ok, this.session, this.error});

  factory LoginResult.success(Session session) => LoginResult._(ok: true, session: session);
  factory LoginResult.failure(String error) => LoginResult._(ok: false, error: error);
}
