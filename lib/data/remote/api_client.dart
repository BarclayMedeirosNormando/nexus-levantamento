import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config.dart';

/// Erro de rede/API — separado de erro "de negócio" (que vem como
/// `{ ok: false, error: "..." }` no corpo, HTTP 200 normal).
class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

const _redirectStatusCodes = {301, 302, 303, 307, 308};

/// Cliente HTTP fino — todo endpoint do backend é um POST na mesma URL, com
/// `action` no corpo (ver doPost() em claude/backend_levantamento.gs). Esta
/// classe só sabe montar a chamada e decodificar a resposta; não sabe nada
/// de token — quem chama passa o token pronto quando precisa (auth_service).
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<http.Response> _send(String method, Uri uri, {String? body}) async {
    // followRedirects = false de propósito: não queremos depender do
    // comportamento automático do cliente HTTP (que varia por plataforma).
    // O Apps Script Web App responde ao POST em /exec com um 302 pra uma
    // URL de conteúdo (script.googleusercontent.com/macros/echo?...) — a
    // execução do doPost() já aconteceu nesse primeiro hop; o(s) hop(s)
    // seguinte(s) só buscam o resultado já pronto. Seguimos isso na mão,
    // hop a hop, pra ter controle total e poder diagnosticar se travar.
    final request = http.Request(method, uri)..followRedirects = false;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = body;
    }
    // O timeout envolve o envio E a leitura do corpo da resposta — um
    // `.timeout()` só no `send()` não pega uma resposta que chegou (cabeçalho
    // 200/302) mas travou no meio do corpo (ex: payload grande do
    // pull_referencia). Sem isso, a tela podia ficar "Sincronizando..." pra
    // sempre num caso desses, sem nunca cair no catch.
    return await (() async {
      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    })().timeout(AppConfig.networkTimeout);
  }

  Future<Map<String, dynamic>> call(String action, Map<String, dynamic> body) async {
    final payload = {'action': action, ...body};
    final baseUri = Uri.parse(AppConfig.baseUrl);
    http.Response response;

    try {
      response = await _send('POST', baseUri, body: jsonEncode(payload));

      var hops = 0;
      while (_redirectStatusCodes.contains(response.statusCode) && hops < 5) {
        final location = response.headers['location'];
        if (location == null || location.isEmpty) {
          throw ApiException(
            'Redirecionamento sem destino (HTTP ${response.statusCode}, sem header location).',
          );
        }
        final redirectUri = baseUri.resolve(location);
        response = await _send('GET', redirectUri);
        hops++;
      }

      if (_redirectStatusCodes.contains(response.statusCode)) {
        throw ApiException(
          'Muitos redirecionamentos (parou em HTTP ${response.statusCode} após $hops passo(s)).',
        );
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      // Sem rede, timeout, DNS etc. — quem chama decide o que fazer (ex:
      // login exige rede na primeira vez; outras ações toleram estar offline
      // e ficam só na fila local).
      throw ApiException('Sem conexão com o servidor. Tente novamente quando tiver internet.\n($e)');
    }

    if (response.statusCode != 200) {
      throw ApiException(
        'Erro do servidor (HTTP ${response.statusCode}).\n${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
      );
    }

    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Resposta inesperada do servidor.\n${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
    }

    return decoded;
  }
}
