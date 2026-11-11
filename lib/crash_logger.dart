import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Catches ALL unhandled errors and saves them to a readable log file.
/// View the log in Settings → View Crash Log
class CrashLogger {
  static final CrashLogger _instance = CrashLogger._internal();
  factory CrashLogger() => _instance;
  CrashLogger._internal();

  static const int _maxLogSizeBytes = 512 * 1024; // 500KB max
  static const String _logFileName = 'veilchat_crash_log.txt';

  /// Initialize — call this at the very start of main()
  static Future<void> init() async {
    // Catch Flutter framework errors (widget build errors etc)
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details); // still show in console
      CrashLogger()._writeLog('FLUTTER_ERROR', details.toString());
    };

    // Catch all other Dart errors (async, isolate etc)
    PlatformDispatcher.instance.onError = (error, stack) {
      CrashLogger()._writeLog('DART_ERROR', '$error\n\nStack trace:\n$stack');
      return false; // let default handler also run
    };

    debugPrint('✅ CrashLogger initialized');
  }

  Future<void> _writeLog(String type, String message) async {
    try {
      final file = await _getLogFile();
      final timestamp = DateTime.now().toIso8601String();
      final entry = '\n[$timestamp] [$type]\n$message\n${'─' * 60}\n';

      // Rotate log if too large
      if (await file.exists()) {
        final size = await file.length();
        if (size > _maxLogSizeBytes) {
          // Keep only last half of log
          final content = await file.readAsString();
          final half = content.substring(content.length ~/ 2);
          await file.writeAsString('=== LOG ROTATED AT $timestamp ===\n$half');
        }
      }

      await file.writeAsString(entry, mode: FileMode.append);
    } catch (e) {
      debugPrint('❌ CrashLogger write failed: $e');
    }
  }

  /// Log a custom event or error manually
  Future<void> log(String tag, String message) async {
    debugPrint('[$tag] $message');
    await _writeLog(tag, message);
  }

  Future<File> _getLogFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_logFileName');
  }

  /// Read entire log content
  Future<String> readLog() async {
    try {
      final file = await _getLogFile();
      if (!await file.exists()) return 'No crashes logged yet. ✅';
      return await file.readAsString();
    } catch (e) {
      return 'Error reading log: $e';
    }
  }

  /// Clear the log
  Future<void> clearLog() async {
    try {
      final file = await _getLogFile();
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('❌ CrashLogger clear failed: $e');
    }
  }

  /// Get log file size
  Future<String> getLogSize() async {
    try {
      final file = await _getLogFile();
      if (!await file.exists()) return '0 KB';
      final bytes = await file.length();
      if (bytes < 1024) return '$bytes B';
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } catch (_) {
      return 'Unknown';
    }
  }
}
