import 'package:flutter/material.dart';
import 'core/route_observer.dart';
import 'core/theme.dart';
import 'data/remote/auth_service.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';

class NexusLevantamentoApp extends StatelessWidget {
  const NexusLevantamentoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nexus Levantamento',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorObservers: [routeObserver],
      home: const _StartupGate(),
    );
  }
}

/// Decide a tela inicial: se já existe uma sessão salva (login anterior),
/// pula direto pra Home — é o que permite o app funcionar offline depois do
/// primeiro login, sem pedir login de novo toda vez.
class _StartupGate extends StatelessWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Session?>(
      future: AuthService().getSavedSession(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: AppColors.navy,
            body: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }
        final session = snapshot.data;
        if (session == null) return const LoginScreen();
        return HomeScreen(session: session);
      },
    );
  }
}
