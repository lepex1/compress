import 'dart:io' show stdout, Platform, File, Directory, FileMode;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum LogLevel { debug, success, process, warning, error }

class LogEntry {
  final LogLevel level;
  final String message;
  final String timestamp;
  final String plainLine;
  final String ansiLine;

  const LogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
    required this.plainLine,
    required this.ansiLine,
  });
}

class CompressLogger extends ChangeNotifier {
  static final CompressLogger _instance = CompressLogger._();
  factory CompressLogger() => _instance;
  CompressLogger._() {
    _initLogFile();
  }

  final List<String> _buffer = [];
  final List<LogEntry> _entries = [];
  File? _logFile;

  List<LogEntry> get entries => _entries;

  void _initLogFile() {
    try {
      final appData = Platform.environment['APPDATA'] ?? '';
      final dir = Directory(p.join(appData, 'compress'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final oldLog = File(p.join(dir.path, 'compress-old.log'));
      final curLog = File(p.join(dir.path, 'compress.log'));
      if (oldLog.existsSync()) oldLog.deleteSync();
      if (curLog.existsSync()) curLog.renameSync(p.join(dir.path, 'compress-old.log'));
      _logFile = File(p.join(dir.path, 'compress.log'));
    } catch (_) {}
  }

  static const _colors = {
    LogLevel.debug: '\x1B[94m',
    LogLevel.success: '\x1B[92m',
    LogLevel.process: '\x1B[96m',
    LogLevel.warning: '\x1B[93m',
    LogLevel.error: '\x1B[91m',
  };
  static const _bold = '\x1B[1m';
  static const _reset = '\x1B[0m';

  void _log(String message, LogLevel level) {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final ts = '$h:$m:$s';
    final color = _colors[level] ?? '';
    final tag = level == LogLevel.warning || level == LogLevel.error
        ? '$_bold${level.name.toUpperCase()}$_reset'
        : level.name.toUpperCase();
    final ansiLine = '$color[$ts] [$tag] $message$_reset';
    final plainLine = '[$ts] [${level.name.toUpperCase()}] $message';
    stdout.writeln(ansiLine);
    _buffer.add(plainLine);
    _entries.add(LogEntry(
      level: level,
      message: message,
      timestamp: ts,
      plainLine: plainLine,
      ansiLine: ansiLine,
    ));
    notifyListeners();
    try {
      _logFile?.writeAsStringSync('$ansiLine\n', mode: FileMode.append);
    } catch (_) {}
  }

  List<String> getLogs() => List.unmodifiable(_buffer);

  String? get logFilePath => _logFile?.path;

  void debug(String message) => _log(message, LogLevel.debug);
  void success(String message) => _log(message, LogLevel.success);
  void process(String message) => _log(message, LogLevel.process);
  void warning(String message) => _log(message, LogLevel.warning);
  void error(String message) => _log(message, LogLevel.error);
}
