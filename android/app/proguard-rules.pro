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
