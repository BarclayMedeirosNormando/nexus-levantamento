import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'local/database.dart';
import 'remote/api_client.dart';
import 'remote/auth_service.dart';

class FotoUploadResult {
  final int enviadas;
  final int falhas;
  const FotoUploadResult({required this.enviadas, required this.falhas});
}

/// Sobe fotos de equipamento (etiqueta/equipamento) tiradas offline em campo.
///
/// Tirar a foto (ver `equipamento_form_screen.dart`) NUNCA exige internet —
/// só grava o caminho do arquivo no aparelho, em
/// `foto_etiqueta_local_path`/`foto_equipamento_local_path` (colunas só
/// locais, ver comentário de `_dbVersion = 3` em `database.dart`). Esta
/// classe é quem de fato sobe o arquivo (ação `upload_foto`, mesmo endpoint
/// que já existia pra assinatura em `conclusao_screen.dart`) e preenche a
/// URL definitiva em `foto_etiqueta_url`/`foto_equipamento_url` — são esses
/// dois campos (nunca o caminho local) que viajam no `push_levantamento`
/// (ver `LevantamentoSyncService._equipamentoParaApi`).
///
/// Chamada a cada sync (manual ou automático — ver `SyncEngine`) ANTES do
/// push, assim a URL já pode ir junto se o upload terminar a tempo; se não
/// terminar (ou não tiver internet), a próxima sincronização tenta de novo —
/// nada aqui é "tudo ou nada": cada foto tem seu próprio try/catch, uma
/// falha isolada (arquivo apagado, upload recusado) nunca trava as demais.
class FotoUploadService {
  FotoUploadService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();
  final ApiClient _api;

  // (coluna do caminho local, coluna da URL remota, rótulo pro nome do arquivo)
  static const _campos = [
    ('foto_etiqueta_local_path', 'foto_etiqueta_url', 'etiqueta'),
    ('foto_equipamento_local_path', 'foto_equipamento_url', 'equipamento'),
  ];

  Future<FotoUploadResult> enviarPendentes(Session session) async {
    final db = await AppDatabase.instance.database;
    var enviadas = 0;
    var falhas = 0;

    for (final (colunaLocal, colunaUrl, rotulo) in _campos) {
      final rows = await db.query(
        'equipamentos',
        columns: ['id', colunaLocal],
        where: "$colunaLocal IS NOT NULL AND $colunaLocal != '' AND ($colunaUrl IS NULL OR $colunaUrl = '')",
      );

      for (final row in rows) {
        final id = row['id'] as String;
        final caminho = row[colunaLocal] as String?;
        if (caminho == null || caminho.isEmpty) continue;

        try {
          final arquivo = File(caminho);
          if (!await arquivo.exists()) {
            // Arquivo sumiu (ex: cache do app foi limpo) — não tem o que
            // reenviar, mas também não é um erro que valha ficar tentando
            // pra sempre: só pula, sem contar como falha nem sucesso.
            continue;
          }

          // Comprime antes de mandar (a mesma preocupação de banda/tamanho
          // que já vale pro resto do sync — ver AppConfig.networkTimeout).
          // Se a compressão falhar por algum motivo, sobe o arquivo original
          // em vez de desistir.
          Uint8List? comprimido;
          try {
            comprimido = await FlutterImageCompress.compressWithFile(
              caminho,
              // Reduzido de 1280/70 pra 1024/62 (2026-09-14, pedido do
              // Barclay: "imagens menores sem perder qualidade") — pra foto
              // de documentação de campo (equipamento/galeria), a perda
              // visual entre essas duas configurações é imperceptível na
              // tela, mas o arquivo final fica bem menor (menos dado pra
              // subir em rede de escola instável, menos espaço na planilha).
              minWidth: 1024,
              minHeight: 1024,
              quality: 62,
            );
          } catch (_) {
            comprimido = null;
          }
          final bytes = comprimido ?? await arquivo.readAsBytes();

          final resposta = await _api.call('upload_foto', {
            'token': session.token,
            'base64': base64Encode(bytes),
            'nome_arquivo': '${rotulo}_$id.jpg',
            'mime_type': 'image/jpeg',
          });

          final url = resposta['ok'] == true ? resposta['url']?.toString() : null;
          if (url == null || url.isEmpty) {
            falhas++;
            continue;
          }

          await db.update('equipamentos', {colunaUrl: url}, where: 'id = ?', whereArgs: [id]);
          enviadas++;
        } catch (_) {
          // Sem rede, timeout, etc. — a próxima sincronização tenta de novo
          // (o local_path continua lá, a url continua vazia).
          falhas++;
        }
      }
    }

    final galeria = await _enviarFotosLevantamentoPendentes(session);
    enviadas += galeria.enviadas;
    falhas += galeria.falhas;

    return FotoUploadResult(enviadas: enviadas, falhas: falhas);
  }

  /// Conta fotos com caminho local mas sem URL ainda — mesma condição usada
  /// por [enviarPendentes], só que sem subir nada (2026-09-12, indicador de
  /// pendências da Home).
  Future<int> contarPendentes() async {
    final db = await AppDatabase.instance.database;
    var total = 0;
    for (final (colunaLocal, colunaUrl, _) in _campos) {
      final resultado = await db.rawQuery('''
        SELECT COUNT(*) AS c FROM equipamentos
        WHERE $colunaLocal IS NOT NULL AND $colunaLocal != '' AND ($colunaUrl IS NULL OR $colunaUrl = '')
      ''');
      total += (resultado.first['c'] as int?) ?? 0;
    }
    final resultadoGaleria = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM fotos_levantamento
      WHERE foto_local_path IS NOT NULL AND foto_local_path != '' AND (foto_url IS NULL OR foto_url = '')
    ''');
    total += (resultadoGaleria.first['c'] as int?) ?? 0;
    return total;
  }

  /// Sobe fotos da galeria geral do levantamento (`fotos_levantamento` —
  /// Fachada/Laboratório/Roteador/Equipamento/Documento/Outro, ver
  /// `FotosLevantamentoRepository`). Mesmo mecanismo de [enviarPendentes]
  /// pros campos de equipamento (`upload_foto`, compressão, um try/catch por
  /// foto), só que cada LINHA já é uma foto (não duas colunas por linha) —
  /// por isso um método separado em vez de reaproveitar [_campos].
  Future<FotoUploadResult> _enviarFotosLevantamentoPendentes(Session session) async {
    final db = await AppDatabase.instance.database;
    var enviadas = 0;
    var falhas = 0;

    final rows = await db.query(
      'fotos_levantamento',
      columns: ['id', 'foto_local_path', 'tipo_foto'],
      where: "foto_local_path IS NOT NULL AND foto_local_path != '' AND (foto_url IS NULL OR foto_url = '')",
    );

    for (final row in rows) {
      final id = row['id'] as String;
      final caminho = row['foto_local_path'] as String?;
      if (caminho == null || caminho.isEmpty) continue;

      try {
        final arquivo = File(caminho);
        if (!await arquivo.exists()) continue; // arquivo sumiu — nada a reenviar, não conta como falha

        Uint8List? comprimido;
        try {
          comprimido = await FlutterImageCompress.compressWithFile(
            caminho,
            // Mesmo ajuste da compressão de foto de equipamento acima.
            minWidth: 1024,
            minHeight: 1024,
            quality: 62,
          );
        } catch (_) {
          comprimido = null;
        }
        final bytes = comprimido ?? await arquivo.readAsBytes();

        final tipo = (row['tipo_foto'] as String? ?? 'foto').toLowerCase();
        final resposta = await _api.call('upload_foto', {
          'token': session.token,
          'base64': base64Encode(bytes),
          'nome_arquivo': '${tipo}_$id.jpg',
          'mime_type': 'image/jpeg',
        });

        final url = resposta['ok'] == true ? resposta['url']?.toString() : null;
        if (url == null || url.isEmpty) {
          falhas++;
          continue;
        }

        await db.update('fotos_levantamento', {'foto_url': url}, where: 'id = ?', whereArgs: [id]);
        enviadas++;
      } catch (_) {
        falhas++;
      }
    }

    return FotoUploadResult(enviadas: enviadas, falhas: falhas);
  }
}
