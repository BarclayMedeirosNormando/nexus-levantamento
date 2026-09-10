import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app.dart';

void main() {
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

  runApp(const NexusLevantamentoApp());
}
