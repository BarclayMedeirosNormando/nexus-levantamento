import 'package:flutter/material.dart';

/// Observador global de rotas — usado pela Home pra saber quando o usuário
/// voltou de outra tela (ex.: depois de abrir/fechar um levantamento) e
/// recarregar a seção "Levantamentos em andamento" sem precisar de um botão
/// manual de atualizar. Registrado em `app.dart` (`navigatorObservers`).
final routeObserver = RouteObserver<PageRoute<void>>();
