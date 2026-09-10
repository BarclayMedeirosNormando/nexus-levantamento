# Nexus Levantamento

App Flutter offline-first de levantamento de inventário escolar (SEECT-PB),
falando com o backend Apps Script em `claude/backend_levantamento.gs`
(projeto Claude "Inventario SEE - appsheet").

## O que já existe (v0.1 — primeira fatia)

- Estrutura do projeto (`lib/core`, `lib/data`, `lib/features`).
- Banco local SQLite espelhando as 12 abas do backend, com controle de
  sincronização (`sync_status`) nas tabelas transacionais.
- Cliente HTTP genérico pro Web App (`lib/data/remote/api_client.dart`).
- Login real contra o backend, com sessão salva em secure storage
  (`lib/data/remote/auth_service.dart`, `lib/features/auth/login_screen.dart`).
- Sincronização de dados de referência (`pull_referencia`) — escolas,
  servidores, contratos de internet, ambientes padrão, catálogo de
  equipamentos — salvos no SQLite local (`lib/data/sync_service.dart`).
- Tela Home (`lib/features/home/home_screen.dart`) — stub funcional: mostra
  quem está logado e tem um botão "Sincronizar dados" que já bate no
  backend de verdade.

## O que falta (próximas fatias, em ordem)

1. Lista de escolas de verdade na Home (busca, cards) — hoje é só um botão
   de teste de sync.
2. Tela de detalhe da escola + abertura de levantamento.
3. Seleção/lista de ambientes (com os ambientes padrão pré-marcados).
4. Formulário de equipamento (captura de foto, código de barras/OCR pra
   tombamento/série, checagem local de duplicidade).
5. Conectividade e Wifi.
6. Conclusão (assinatura, responsável, `push_levantamento`).
7. Fila de sincronização em background (`workmanager`) — hoje o sync é só
   manual (botão), falta subir levantamentos pendentes automaticamente
   quando a internet voltar.

Ver `claude/spec_app_flutter_levantamento.md` no projeto Claude pro desenho
completo de telas, regras de negócio e decisões já tomadas.

## Como rodar

Este projeto foi montado sem passar pelo `flutter create` (o ambiente onde
foi gerado não tem o Flutter SDK instalado), então as pastas de plataforma
(`android/`, `ios/`, etc.) **não existem ainda**. Pra rodar:

1. Em uma pasta separada, rode:
   ```
   flutter create --org br.gov.pb.see --project-name nexus_levantamento temp_scaffold
   ```
2. Copie as pastas `android/`, `ios/`, `linux/`, `macos/`, `windows/`, `web/`
   (as que você for usar) de dentro de `temp_scaffold/` pra dentro desta
   pasta (`nexus_levantamento/`), substituindo o `pubspec.yaml` gerado pelo
   `flutter create` — **mantenha o `pubspec.yaml` que já está aqui**, ele já
   tem as dependências certas.
3. Apague `temp_scaffold/`.
4. Rode `flutter pub get`.
5. Rode `flutter run` com um dispositivo/emulador conectado.

Se a URL do Web App mudar no futuro (ex: nova implantação do zero, não só
"Nova versão"), atualize `lib/core/config.dart`.
