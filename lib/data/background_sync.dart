import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'remote/auth_service.dart';
import 'sync_engine.dart';

const String _nomeTarefaPeriodica = 'nexus-sync-periodico';
const String _nomeTarefaUnica = 'nexus-sync-tarefa';

/// Sync automático em segundo plano (2026-09-12) — só Android/iOS
/// (`workmanager` não tem implementação desktop; `main.dart` só chama
/// [inicializarSyncEmBackground] nessas plataformas). Não substitui o botão
/// "Sincronizar dados" nem o disparo ao reconectar (ver `HomeScreen`) — é
/// um reforço pra quando o app fica um tempo fechado ou em segundo plano
/// sem ninguém tocar em nada: o SO acorda o app periodicamente (mínimo 15
/// min, imposto pelo próprio Android/WorkManager) só pra rodar o
/// [SyncEngine], mesmo com o app fechado.
///
/// AVISO — esta é a parte do app que menos dá pra garantir sem testar num
/// aparelho/emulador Android de verdade: o isolate que o WorkManager cria
/// pra rodar [callbackDispatcher] é separado do isolate principal do app, e
/// plugins que dependem de canais de plataforma (sqflite,
/// flutter_secure_storage, usados por [AuthService]/[SyncEngine]) às vezes
/// precisam de ajuste fino nesse cenário. Se o sync automático não
/// funcionar de primeira, veja os logs do `adb logcat` filtrando por
/// "WM-" (tag do WorkManager) — o sync manual e o disparo ao reconectar
/// continuam funcionando normalmente independente disso.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final session = await AuthService().getSavedSession();
      if (session == null) {
        // Ninguém logado neste aparelho — nada pra sincronizar agora.
        return Future.value(true);
      }
      await SyncEngine().sincronizarTudo(session);
    } catch (_) {
      // Sem rede, erro de servidor, etc. — não é uma falha "fatal": o
      // próximo ciclo periódico (ou o sync manual/ao reconectar) tenta de
      // novo sozinho. Retorna sucesso mesmo assim pra não acionar retry
      // agressivo do WorkManager em cima de um problema que só a próxima
      // janela de 15 min resolve de qualquer forma.
    }
    return Future.value(true);
  });
}

/// Chamado uma vez em `main.dart`, só em Android/iOS. Registra a tarefa
/// periódica (mínimo 15 min é imposto pela própria plataforma — não dá pra
/// pedir mais frequente que isso). `NetworkType.connected` evita a tarefa
/// nem começar a rodar sem rede nenhuma — economiza bateria em vez de
/// acordar o app só pra falhar na primeira chamada.
Future<void> inicializarSyncEmBackground() async {
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  await Workmanager().registerPeriodicTask(
    _nomeTarefaPeriodica,
    _nomeTarefaUnica,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
  );
}
