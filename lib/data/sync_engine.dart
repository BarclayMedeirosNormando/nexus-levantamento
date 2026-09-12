import 'foto_upload_service.dart';
import 'levantamento_sync_service.dart';
import 'remote/auth_service.dart';
import 'sync_service.dart';

class SyncEngineResult {
  final int fotosEnviadas;
  final int fotosComFalha;
  final PushResult push;
  final PullAtivosResult pull;
  const SyncEngineResult({
    required this.fotosEnviadas,
    required this.fotosComFalha,
    required this.push,
    required this.pull,
  });
}

/// Ponto único que sabe "sincronizar tudo", na ordem certa — usado tanto
/// pelo botão manual (`HomeScreen._sincronizar`) quanto pelo sync automático
/// (background via `workmanager`, ver `background_sync.dart`, e o disparo
/// ao reconectar em `HomeScreen`). Antes desta classe existir, a Home
/// chamava os três passos direto; centralizar aqui evita que o caminho
/// manual e o automático divirjam com o tempo.
///
/// Ordem importa (mesmo raciocínio de antes, ver `HomeScreen._sincronizar`):
/// 1) sobe fotos pendentes primeiro — se der tempo, a URL já vai junto no
///    push seguinte, em vez de esperar mais um ciclo;
/// 2) sobe o que este aparelho tem pendente (`pushPendentes`);
/// 3) baixa referência (`pullReferencia`);
/// 4) baixa levantamentos ativos (`pullLevantamentosAtivos`).
class SyncEngine {
  SyncEngine({
    FotoUploadService? fotoUploadService,
    LevantamentoSyncService? levantamentoSyncService,
    SyncService? syncService,
  })  : _fotoUploadService = fotoUploadService ?? FotoUploadService(),
        _levantamentoSyncService = levantamentoSyncService ?? LevantamentoSyncService(),
        _syncService = syncService ?? SyncService();

  final FotoUploadService _fotoUploadService;
  final LevantamentoSyncService _levantamentoSyncService;
  final SyncService _syncService;

  Future<SyncEngineResult> sincronizarTudo(Session session) async {
    final fotos = await _fotoUploadService.enviarPendentes(session);
    final push = await _levantamentoSyncService.pushPendentes(session);
    await _syncService.pullReferencia(session);
    final pull = await _levantamentoSyncService.pullLevantamentosAtivos(session);

    return SyncEngineResult(
      fotosEnviadas: fotos.enviadas,
      fotosComFalha: fotos.falhas,
      push: push,
      pull: pull,
    );
  }
}
