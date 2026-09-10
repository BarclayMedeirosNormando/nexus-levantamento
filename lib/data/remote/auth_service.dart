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

  const Session({
    required this.token,
    required this.matricula,
    required this.papel,
    required this.nome,
  });

  bool get isAdm => papel == 'ADM';
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
    );

    await _saveSession(session);
    return LoginResult.success(session);
  }

  Future<void> _saveSession(Session session) async {
    await _storage.write(key: _kToken, value: session.token);
    await _storage.write(key: _kMatricula, value: session.matricula);
    await _storage.write(key: _kPapel, value: session.papel);
    await _storage.write(key: _kNome, value: session.nome);
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
    );
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
