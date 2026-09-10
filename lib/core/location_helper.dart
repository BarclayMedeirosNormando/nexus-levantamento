import 'package:geolocator/geolocator.dart';

/// Captura de GPS na abertura do levantamento (§5/Tela 4 do spec) — sempre
/// "best effort": nunca trava nem impede abrir o levantamento se não
/// conseguir localização (permissão negada, GPS desligado, sem hardware —
/// caso comum testando em desktop). Se falhar, o levantamento é aberto sem
/// coordenadas; não há retry automático aqui.
class LocationHelper {
  LocationHelper._();

  static Future<({double lat, double long})?> tentarCapturar() async {
    try {
      final servicoAtivo = await Geolocator.isLocationServiceEnabled();
      if (!servicoAtivo) return null;

      var permissao = await Geolocator.checkPermission();
      if (permissao == LocationPermission.denied) {
        permissao = await Geolocator.requestPermission();
      }
      if (permissao == LocationPermission.denied || permissao == LocationPermission.deniedForever) {
        return null;
      }

      // `desiredAccuracy`/`timeLimit` (em vez de `locationSettings`) porque
      // é a assinatura que existe na versão do geolocator pinada no
      // pubspec.yaml (12.0.0) — `locationSettings` só chegou em versões
      // mais novas do pacote.
      final posicao = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      );
      return (lat: posicao.latitude, long: posicao.longitude);
    } catch (_) {
      // Qualquer erro (plugin não suportado na plataforma, timeout, sem
      // hardware de GPS etc.) — degrada pra "sem coordenadas", não propaga.
      return null;
    }
  }
}
