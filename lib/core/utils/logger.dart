// lib/core/utils/logger.dart

import 'package:flutter/foundation.dart';

class AppLogger {
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
