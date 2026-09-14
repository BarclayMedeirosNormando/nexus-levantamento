# ML Kit text recognition (google_mlkit_text_recognition, usado no OCR da
# etiqueta em equipamento_form_screen.dart) referencia no seu código nativo
# reconhecedores opcionais de outros alfabetos (chinês, japonês, coreano,
# devanágari), mesmo o app só usando o reconhecedor padrão (latino). Essas
# classes nunca são chamadas de verdade, mas o R8 (minificação do build
# --release; o build --debug não passa por isso) enxerga a referência no
# bytecode do plugin e falha porque as bibliotecas desses outros scripts
# não são dependência do projeto (nunca vão ser, o app não precisa delas).
# Erro visto (2026-09-13): "Missing class
# com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions..." no
# 'flutter build apk --release'. Como o app nunca usa esses scripts, é
# seguro dizer ao R8 pra não se preocupar com essas classes ausentes.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# 2026-09-14: scanner de codigo de barras (mobile_scanner) funcionava
# perfeitamente em 'flutter run' (debug, sem minificacao) mas falhava com
# "Nao foi possivel abrir a camera" / NullPointerException generica so em
# 'flutter build apk --release' (com R8) - confirmado via logcat de debug
# mostrando CameraX abrindo a camera com sucesso (Camera@...[id=0] OPEN,
# captura configurada, TFLite/barhopper carregando o modelo de leitura de
# codigo de barras normalmente). Classico sintoma de R8 removendo ou
# renomeando algo que essas libs usam via reflection e que so quebra em
# build minificado. mobile_scanner ja traz suas proprias consumer rules,
# mas evidentemente nao cobre tudo - reforcando explicitamente aqui as 3
# libs nativas envolvidas (CameraX, ML Kit barcode scanning bundled, e o
# runtime TensorFlow Lite que elas usam por baixo).
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

-keep class com.google.mlkit.vision.barcode.** { *; }
-keep class com.google.mlkit.vision.codescanner.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-dontwarn com.google.mlkit.vision.barcode.**
-dontwarn com.google.android.gms.internal.mlkit_vision_barcode.**

-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.**

# 2026-09-14 (round 2): mesmo com as regras acima, o app passou a fechar
# sozinho ao ABRIR (antes de qualquer tela) em build --release. Stack trace
# real obtido via 'flutter run --release' (USB) apontou a causa exata:
#   java.lang.RuntimeException: Unable to get provider
#   com.google.mlkit.common.internal.MlKitInitProvider: ... Unsatisfied
#   dependency ... class com.google.mlkit.common.sdkinternal.d
# Todo modulo do ML Kit (inclusive o de barcode) registra um ContentProvider
# (MlKitInitProvider) que roda automaticamente no boot do app pra inicializar
# o sistema interno de injecao de dependencia compartilhado
# (com.google.mlkit.common.**). As regras -keep anteriores cobriram só
# com.google.mlkit.vision.barcode.** (a API especifica de barcode), mas NAO
# cobriam esse nucleo comum usado internamente - o R8 removeu/renomeou parte
# dele, quebrando a inicializacao do app inteiro, nao so do scanner.
-keep class com.google.mlkit.common.** { *; }
-dontwarn com.google.mlkit.common.**

-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-dontwarn com.google.android.gms.internal.mlkit_common.**
