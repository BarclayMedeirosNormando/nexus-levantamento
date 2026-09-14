import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/servidores_repository.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/auth_service.dart';

/// Tela de ADM (2026-09-13) pra resetar a senha de um técnico que esqueceu
/// a própria — sem isso, o único jeito de destravar alguém trancado fora do
/// app era o ADM rodar `definirSenha()` direto no editor do Apps Script.
/// Lista só quem tem LOGIN_HABILITADO=true (ver
/// ServidoresRepository.listarComLogin — 100% local/offline pra abrir a
/// tela); resetar senha é AÇÃO ONLINE (o backend confirma de novo que quem
/// está chamando é ADM — nunca confia só em esconder o botão). Senha
/// resetada é sempre "123456", já marcada como temporária no servidor: na
/// próxima vez que a pessoa logar, o app força a troca antes de deixar
/// entrar (ver TrocarSenhaScreen/LoginScreen).
class GerenciarTecnicosScreen extends StatefulWidget {
  const GerenciarTecnicosScreen({super.key, required this.session});
  final Session session;

  @override
  State<GerenciarTecnicosScreen> createState() => _GerenciarTecnicosScreenState();
}

class _GerenciarTecnicosScreenState extends State<GerenciarTecnicosScreen> {
  final _repo = ServidoresRepository();
  List<ServidorComLogin> _tecnicos = const [];
  bool _carregando = true;
  String? _resetandoMatricula;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final lista = await _repo.listarComLogin();
    if (!mounted) return;
    setState(() {
      _tecnicos = lista;
      _carregando = false;
    });
  }

  Future<void> _confirmarReset(ServidorComLogin tecnico) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resetar senha'),
        content: Text(
          'A senha de ${tecnico.nome} (matrícula ${tecnico.matricula}) será redefinida para 123456. '
          'Ele(a) precisará trocá-la ao entrar da próxima vez. Confirmar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Resetar')),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _resetandoMatricula = tecnico.matricula);
    try {
      await _repo.resetarSenha(matricula: tecnico.matricula, session: widget.session);
      if (!mounted) return;
      AppSnackbar.sucesso(context, 'Senha de ${tecnico.nome} resetada para 123456.');
    } on ApiException catch (e) {
      if (!mounted) return;
      AppSnackbar.erro(context, 'Erro: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.erro(context, 'Erro inesperado: $e');
    } finally {
      if (mounted) setState(() => _resetandoMatricula = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gerenciar técnicos')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _tecnicos.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Nenhum servidor com login habilitado sincronizado ainda. '
                      'Sincronize os dados e tente de novo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tecnicos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final tecnico = _tecnicos[index];
                    final resetando = _resetandoMatricula == tecnico.matricula;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tecnico.nome,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Matrícula ${tecnico.matricula} · ${tecnico.papel}',
                                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: resetando ? null : () => _confirmarReset(tecnico),
                            icon: resetando
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.lock_reset_rounded, size: 18),
                            label: const Text('Resetar senha'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
