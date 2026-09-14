import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/auth_service.dart';
import '../home/home_screen.dart';

/// Tela de troca de senha (2026-09-13). Dois modos:
/// - [obrigatorio] = true: entrada forçada logo após login com senha
///   temporária ou resetada pelo ADM (ver LoginScreen/app.dart) — sem botão
///   de voltar/cancelar; o gesto de voltar do Android é bloqueado (PopScope
///   com canPop: false). Só sai daqui trocando a senha de verdade.
/// - [obrigatorio] = false: acesso voluntário (Home → "Trocar minha
///   senha") — AppBar normal, com botão de voltar.
class TrocarSenhaScreen extends StatefulWidget {
  const TrocarSenhaScreen({super.key, required this.session, this.obrigatorio = false});

  final Session session;
  final bool obrigatorio;

  @override
  State<TrocarSenhaScreen> createState() => _TrocarSenhaScreenState();
}

class _TrocarSenhaScreenState extends State<TrocarSenhaScreen> {
  final _authService = AuthService();
  final _novaSenhaController = TextEditingController();
  final _confirmarController = TextEditingController();

  bool _obscureNova = true;
  bool _obscureConfirmar = true;
  bool _loading = false;
  String? _erro;

  @override
  void dispose() {
    _novaSenhaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final novaSenha = _novaSenhaController.text;
    final confirmar = _confirmarController.text;

    if (novaSenha.length < 6) {
      setState(() => _erro = 'A nova senha precisa ter pelo menos 6 caracteres.');
      return;
    }
    if (novaSenha != confirmar) {
      setState(() => _erro = 'As senhas não conferem.');
      return;
    }

    setState(() {
      _loading = true;
      _erro = null;
    });

    try {
      final sessionAtualizada = await _authService.trocarSenha(
        session: widget.session,
        novaSenha: novaSenha,
      );
      if (!mounted) return;

      if (widget.obrigatorio) {
        // Veio do login (pushReplacement da LoginScreen) — troca por essa
        // mesma via, sem deixar a tela de troca na pilha.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomeScreen(session: sessionAtualizada)),
        );
      } else {
        // Acesso voluntário (Home → "Trocar minha senha") — só volta,
        // avisando que deu certo.
        AppSnackbar.sucesso(context, 'Senha alterada com sucesso.');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro inesperado: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final corpo = SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_reset_rounded, size: 40, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              widget.obrigatorio ? 'Defina uma nova senha' : 'Trocar minha senha',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.ink),
            ),
            const SizedBox(height: 6),
            if (widget.obrigatorio)
              const Text(
                'Sua senha atual é temporária. Antes de continuar, defina uma senha só sua.',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            const SizedBox(height: 24),
            TextField(
              controller: _novaSenhaController,
              obscureText: _obscureNova,
              enabled: !_loading,
              decoration: InputDecoration(
                labelText: 'NOVA SENHA',
                suffixIcon: IconButton(
                  icon: Icon(_obscureNova ? Icons.visibility_off : Icons.visibility),
                  tooltip: _obscureNova ? 'Mostrar senha' : 'Ocultar senha',
                  onPressed: () => setState(() => _obscureNova = !_obscureNova),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmarController,
              obscureText: _obscureConfirmar,
              enabled: !_loading,
              onSubmitted: (_) => _confirmar(),
              decoration: InputDecoration(
                labelText: 'CONFIRMAR NOVA SENHA',
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirmar ? Icons.visibility_off : Icons.visibility),
                  tooltip: _obscureConfirmar ? 'Mostrar senha' : 'Ocultar senha',
                  onPressed: () => setState(() => _obscureConfirmar = !_obscureConfirmar),
                ),
              ),
            ),
            if (_erro != null) ...[
              const SizedBox(height: 12),
              Text(_erro!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _confirmar,
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Salvar nova senha'),
              ),
            ),
          ],
        ),
      ),
    );

    if (!widget.obrigatorio) {
      return Scaffold(appBar: AppBar(title: const Text('Trocar senha')), body: corpo);
    }

    // Modo obrigatório: sem AppBar/botão de voltar, e o gesto de voltar do
    // Android é bloqueado (canPop: false) — só sai trocando a senha mesmo.
    return PopScope(
      canPop: false,
      child: Scaffold(body: corpo),
    );
  }
}
