/// Configuração central da API — único lugar que sabe o endereço do backend.
///
/// O backend é o Apps Script Web App (ver claude/backend_levantamento.gs no
/// projeto). Toda chamada é um POST nessa mesma URL, com
/// `{ "action": "...", ...resto do corpo }` no body — o roteamento por
/// "action" acontece dentro do doPost() do backend.
class AppConfig {
  AppConfig._();

  /// URL da implantação ativa do Web App (Implantar → Gerenciar implantações).
  /// Se um dia a implantação for recriada do zero (não só uma "Nova versão"
  /// da mesma implantação), essa URL muda e precisa ser atualizada aqui.
  static const String baseUrl =
      'https://script.google.com/macros/s/AKfycbw0jr1xugWN-Yn6K1pzzdgz5Vbn-QsGeLJPWklKeLSb29Q_YNsuabWgM0V04-fpM_bmIg/exec';

  /// Timeout de rede pra qualquer chamada — o app precisa continuar
  /// funcionando offline, então nunca deixamos uma chamada travar a tela
  /// esperando rede ruim indefinidamente.
  ///
  /// 60s (não 20s) porque `pull_referencia` faz o backend varrer a aba
  /// SERVIDORES inteira (29 mil+ linhas) antes de filtrar e responder — isso
  /// é lento no Apps Script/Sheets por natureza. Login e outras ações
  /// pequenas terminam bem antes disso; esse valor só evita timeout
  /// prematuro nas chamadas pesadas.
  static const Duration networkTimeout = Duration(seconds: 60);
}
