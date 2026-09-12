import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/local/servidores_repository.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/auth_service.dart';

/// Bottom sheet de busca de servidor por matrícula ou nome — usado na Tela 8
/// (Conclusão) pra escolher o responsável pela assinatura.
///
/// Decisão de 2026-09-12: a busca não fica mais restrita a quem tem
/// `PODE_ASSINAR=true`. Desde que `pull_referencia` passou a baixar a aba
/// SERVIDORES inteira no sync (ver SyncService/backend), a busca local
/// ([ServidoresRepository.buscarLocal]) já cobre todo mundo sozinha —
/// instantânea e 100% offline. [ServidoresRepository.buscarRemoto] (busca
/// ao vivo no backend, ~26-29 mil linhas) só é chamada como FALLBACK,
/// quando a busca local não acha nada — cobre o caso raro de alguém
/// cadastrado/habilitado DEPOIS do último sync deste aparelho. Isso evita
/// bater na rede a cada tecla à toa, que era o principal motivo da busca
/// parecer lenta antes desta mudança.
Future<ServidorAssinante?> showServidorPickerSheet({
  required BuildContext context,
  required Session session,
}) {
  return showModalBottomSheet<ServidorAssinante>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ServidorPickerSheet(session: session),
  );
}

class _ServidorPickerSheet extends StatefulWidget {
  const _ServidorPickerSheet({required this.session});
  final Session session;

  @override
  State<_ServidorPickerSheet> createState() => _ServidorPickerSheetState();
}

class _ServidorPickerSheetState extends State<_ServidorPickerSheet> {
  final _repo = ServidoresRepository();
  final _queryController = TextEditingController();
  Timer? _debounce;

  List<ServidorAssinante> _resultados = const [];
  bool _carregandoLocal = true;
  bool _buscandoRemoto = false;
  String? _avisoRemoto;

  @override
  void initState() {
    super.initState();
    _buscarLocal('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _buscarLocalEDepoisRemotoSeVazio(query);
  }

  /// Busca local primeiro (instantânea); só dispara a busca online, com um
  /// pequeno debounce, se a local não achou nada — ver comentário da classe
  /// sobre por que isso deixou de rodar em toda tecla.
  Future<void> _buscarLocalEDepoisRemotoSeVazio(String query) async {
    await _buscarLocal(query);
    if (!mounted) return;
    if (_resultados.isNotEmpty) {
      setState(() => _avisoRemoto = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _buscarRemoto(query));
  }

  Future<void> _buscarLocal(String query) async {
    setState(() => _carregandoLocal = true);
    final resultados = await _repo.buscarLocal(query);
    if (!mounted) return;
    setState(() {
      _resultados = resultados;
      _carregandoLocal = false;
    });
  }

  Future<void> _buscarRemoto(String query) async {
    if (query.trim().length < 2) {
      if (mounted) setState(() => _avisoRemoto = null);
      return;
    }
    setState(() {
      _buscandoRemoto = true;
      _avisoRemoto = null;
    });
    try {
      final remotos = await _repo.buscarRemoto(query: query, session: widget.session);
      if (!mounted) return;
      setState(() {
        final jaVistos = _resultados.map((s) => s.matricula).toSet();
        final extras = remotos.where((s) => !jaVistos.contains(s.matricula));
        _resultados = [..._resultados, ...extras];
        _buscandoRemoto = false;
      });
    } on ApiException catch (_) {
      if (!mounted) return;
      setState(() {
        _buscandoRemoto = false;
        _avisoRemoto = 'Sem internet agora — mostrando só quem já está sincronizado neste aparelho.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _buscandoRemoto = false;
        _avisoRemoto = 'Não foi possível completar a busca — mostrando só quem já está sincronizado neste aparelho.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Escolher responsável',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink),
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _queryController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Matrícula ou nome...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _buscandoRemoto
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  onChanged: _onChanged,
                ),
              ),
              if (_avisoRemoto != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(_avisoRemoto!, style: const TextStyle(color: AppColors.warning, fontSize: 12)),
                ),
              const SizedBox(height: 10),
              Expanded(
                child: _carregandoLocal
                    ? const Center(child: CircularProgressIndicator())
                    : _resultados.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Nenhum servidor encontrado. Confira a matrícula/nome ou tente com internet.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.muted, fontSize: 13),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            itemCount: _resultados.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final servidor = _resultados[index];
                              return ListTile(
                                title: Text(servidor.nome),
                                subtitle: Text(servidor.matricula),
                                onTap: () => Navigator.of(context).pop(servidor),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
