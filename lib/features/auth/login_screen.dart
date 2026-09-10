import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/remote/auth_service.dart';
import '../home/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  final _matriculaController = TextEditingController();
  final _senhaController = TextEditingController();

  bool _loading = false;
  String? _erro;

  @override
  void dispose() {
    _matriculaController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    final matricula = _matriculaController.text.trim();
    final senha = _senhaController.text;

    if (matricula.isEmpty || senha.isEmpty) {
      setState(() => _erro = 'Preencha matrícula e senha.');
      return;
    }

    setState(() {
      _loading = true;
      _erro = null;
    });

    try {
      final resultado = await _authService.login(matricula: matricula, senha: senha);
      if (!mounted) return;

      if (!resultado.ok) {
        setState(() {
          _erro = resultado.error;
          _loading = false;
        });
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(session: resultado.session!)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString().replaceFirst('ApiException: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.6, -1),
            end: Alignment(0.8, 1),
            colors: [AppColors.navy, Color(0xFF2B5AA0), AppColors.primary],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          // withOpacity (em vez de withValues) por compatibilidade
                          // com versões um pouco mais antigas do Flutter.
                          color: Colors.white.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withOpacity(0.28)),
                        ),
                        child: const Icon(Icons.school_outlined, color: Colors.white, size: 30),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Nexus Levantamento',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'SEECT-PB · INVENTÁRIO ESCOLAR',
                        style: TextStyle(
                          color: Color(0xFFDBEAFE),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Entrar',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.ink),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Login só precisa de internet uma vez.',
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _matriculaController,
                      keyboardType: TextInputType.number,
                      enabled: !_loading,
                      decoration: const InputDecoration(labelText: 'MATRÍCULA'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _senhaController,
                      obscureText: true,
                      enabled: !_loading,
                      onSubmitted: (_) => _entrar(),
                      decoration: const InputDecoration(labelText: 'SENHA'),
                    ),
                    if (_erro != null) ...[
                      const SizedBox(height: 12),
                      Text(_erro!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _entrar,
                        child: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Entrar'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.access_time_rounded, size: 14, color: AppColors.muted),
                        SizedBox(width: 8),
                        Text(
                          'Depois do primeiro login, funciona offline',
                          style: TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
