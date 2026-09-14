import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/escolas_repository.dart';
import '../../data/local/levantamentos_repository.dart';
import '../../data/local/wifi_repository.dart';

/// Tela 7b do spec — redes wifi da escola dentro deste levantamento (pode
/// ter mais de uma: rede administrativa, rede de alunos, etc.). Formulário
/// simples (SSID + Senha, Senha opcional — tem rede aberta), então usa
/// AlertDialog em vez de tela cheia (só dois TextField, sem chip nenhum —
/// não é o combo AlertDialog+SugestoesChips que travava no Windows, ver
/// comentário em ModeloFormScreen). Mesmo padrão de diálogo simples já
/// usado em ConectividadeScreen._editarEstado.
class WifiScreen extends StatefulWidget {
  const WifiScreen({
    super.key,
    required this.escola,
    required this.levantamento,
    required this.matricula,
  });
  final Escola escola;
  final Levantamento levantamento;
  final String matricula;

  @override
  State<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends State<WifiScreen> {
  final _repo = WifiRepository();
  bool _carregando = true;
  List<RedeWifi> _redes = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final redes = await _repo.listarPorLevantamento(widget.levantamento.id);
    if (!mounted) return;
    setState(() {
      _redes = redes;
      _carregando = false;
    });
  }

  Future<void> _abrirFormulario({RedeWifi? existente}) async {
    final ssidController = TextEditingController(text: existente?.ssid ?? '');
    final senhaController = TextEditingController(text: existente?.senha ?? '');
    var senhaVisivel = false;

    final salvou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existente == null ? 'Adicionar wifi' : 'Editar wifi'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ssidController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'SSID (nome da rede)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: senhaController,
                  obscureText: !senhaVisivel,
                  decoration: InputDecoration(
                    labelText: 'Senha (deixe em branco se a rede for aberta)',
                    suffixIcon: IconButton(
                      icon: Icon(senhaVisivel ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                      onPressed: () => setDialogState(() => senhaVisivel = !senhaVisivel),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (salvou != true) return;

    final ssid = ssidController.text.trim();
    if (ssid.isEmpty) {
      if (!mounted) return;
      AppSnackbar.aviso(context, 'Informe o SSID da rede.');
      return;
    }
    final senha = senhaController.text.trim();

    if (existente == null) {
      await _repo.criar(
        idLevantamento: widget.levantamento.id,
        inep: widget.escola.inep,
        matricula: widget.matricula,
        ssid: ssid,
        senha: senha.isEmpty ? null : senha,
      );
    } else {
      await _repo.atualizar(id: existente.id, ssid: ssid, senha: senha.isEmpty ? null : senha);
    }
    await _carregar();
  }

  Future<void> _remover(RedeWifi rede) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover rede wifi?'),
        content: Text('"${rede.ssid}" — essa ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;
    await _repo.remover(rede.id);
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wifi da escola')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _redes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Nenhuma rede wifi cadastrada ainda. Toque em "Adicionar wifi" pra começar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  itemCount: _redes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final rede = _redes[index];
                    return _WifiCard(
                      rede: rede,
                      onTap: () => _abrirFormulario(existente: rede),
                      onRemover: () => _remover(rede),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Adicionar wifi'),
      ),
    );
  }
}

class _WifiCard extends StatelessWidget {
  const _WifiCard({required this.rede, required this.onTap, required this.onRemover});
  final RedeWifi rede;
  final VoidCallback onTap;
  final VoidCallback onRemover;

  @override
  Widget build(BuildContext context) {
    final temSenha = rede.senha != null && rede.senha!.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
              child: Icon(
                Icons.wifi,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rede.ssid,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink),
                  ),
                  Text(
                    temSenha ? 'Senha: ${rede.senha}' : 'Rede aberta (sem senha)',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
              tooltip: 'Remover',
              onPressed: onRemover,
            ),
          ],
        ),
      ),
    );
  }
}
