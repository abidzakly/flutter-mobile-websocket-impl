// lib/core/utils/logger.dart
//
// Simple logger wrapper. Di production, ganti dengan package seperti
// `logger` atau `talker` untuk output yang lebih kaya (file, remote, dsb).

import 'package:flutter/foundation.dart';

class AppLogger {
  AppLogger._();

  static void debug(String msg) {
    if (kDebugMode) debugPrint('[DEBUG] $msg');
  }

  static void info(String msg) {
    if (kDebugMode) debugPrint('[INFO]  $msg');
  }

  static void warn(String msg) {
    debugPrint('[WARN]  $msg');
  }

  static void error(String msg) {
    debugPrint('[ERROR] $msg');
  }
}