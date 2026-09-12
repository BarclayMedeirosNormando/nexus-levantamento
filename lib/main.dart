import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app.dart';
import 'data/background_sync.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // O pacote sqflite "puro" só tem implementação nativa em Android/iOS.
  // Em desktop (Windows/Linux/macOS) é preciso trocar o databaseFactory
  // pela camada FFI (sqflite_common_ffi) ANTES de qualquer openDatabase —
  // sem isso, toda chamada ao banco local falha com
  // "Bad state: databaseFactory not initialized".
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Sync automático em background (2026-09-12) — `workmanager` só tem
  // implementação Android/iOS (ver background_sync.dart); nem tenta em
  // desktop/web, onde o pacote não faz nada (ou pode nem compilar a
  // chamada nativa). Falha ao registrar (ex: emulador sem Play Services)
  // não devia derrubar o app inteiro — só o sync manual/ao reconectar
  // continuam funcionando normalmente.
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      await inicializarSyncEmBackground();
    } catch (_) {
      // ignore: sync em background é um reforço, não um requisito pra o
      // app funcionar.
    }
  }

  runApp(const NexusLevantamentoApp());
}
