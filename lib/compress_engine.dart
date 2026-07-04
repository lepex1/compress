import 'dart:io';
import 'dart:convert' show utf8, LineSplitter;
import 'dart:collection' show Queue;

import 'package:path/path.dart' as p;
import 'package:archive/archive.dart' show ZipDecoder;

import 'compress_logger.dart';

enum VideoCodec { h264, h265, av1 }
enum SpeedPreset { ultrafast, veryfast, medium, slow, veryslow }
enum AudioCodec { aac, opus, copy, mute }
enum AudioVolume { original, boost3Db, boost6Db, boost10Db, cut3Db }

class EncodingPlan {
  final String resolutionText;
  final int fps;
  final SpeedPreset speed;
  final int videoBitrateKbps;
  final int audioBitrateKbps;

  EncodingPlan({
    required this.resolutionText,
    required this.fps,
    required this.speed,
    required this.videoBitrateKbps,
    required this.audioBitrateKbps,
  });
}

class VideoMetadata {
  Duration duration = Duration.zero;
  int width = 0;
  int height = 0;
  double fps = 0.0;
}

class CancellationToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _onCancel?.call();
  }

  void setOnCancel(void Function() callback) {
    _onCancel = callback;
  }

  void clearOnCancel() {
    _onCancel = null;
  }

  void throwIfCancelled() {
    if (_cancelled) throw CancelledException();
  }
}

class CancelledException implements Exception {}

class CompressEngine {
  static final HttpClient _httpClient =
      HttpClient()..connectionTimeout = const Duration(minutes: 10);

  static bool isVideoFile(String path) {
    if (path.isEmpty) return false;
    final ext = p.extension(path).toLowerCase();
    return ['.mp4', '.avi', '.mov', '.mkv', '.webm'].contains(ext);
  }

  static EncodingPlan calculateEncodingPlan({
    required double targetSizeMb,
    required Duration duration,
    required int originalHeight,
    required String selectedRes,
    required int selectedFps,
    required SpeedPreset selectedPreset,
    required AudioCodec selectedAudio,
  }) {
    final targetBits = targetSizeMb * 1024.0 * 1024.0 * 8.0;
    final usableBits = targetBits * 0.94;
    final durationSec = duration.inSeconds.toDouble();
    if (durationSec <= 0) {
      return EncodingPlan(
        resolutionText: selectedRes,
        fps: selectedFps,
        speed: selectedPreset,
        videoBitrateKbps: 0,
        audioBitrateKbps: 0,
      );
    }

    final totalBitrateBps = usableBits / durationSec;

    double audioBitrateBps = 128000;
    if (selectedAudio == AudioCodec.mute) {
      audioBitrateBps = 0;
    } else if (totalBitrateBps < 200000) {
      audioBitrateBps = 48000;
    } else if (totalBitrateBps < 400000) {
      audioBitrateBps = 96000;
    }

    double videoBitrateBps = totalBitrateBps - audioBitrateBps;
    if (videoBitrateBps < 50000) videoBitrateBps = 50000;

    final videoBitrateKbps = (videoBitrateBps / 1000).round();

    String finalRes = selectedRes;
    if (selectedRes.toLowerCase() == 'auto') {
      final checkHeight = originalHeight > 0 ? originalHeight : 1080;
      if (videoBitrateKbps > 6000 && checkHeight >= 2160) {
        finalRes = '3840x2160';
      } else if (videoBitrateKbps > 3000 && checkHeight >= 1080) {
        finalRes = '1920x1080';
      } else if (videoBitrateKbps > 1200 && checkHeight >= 720) {
        finalRes = '1280x720';
      } else if (videoBitrateKbps > 600 && checkHeight >= 480) {
        finalRes = '854x480';
      } else if (videoBitrateKbps > 300 && checkHeight >= 360) {
        finalRes = '640x360';
      } else if (videoBitrateKbps > 120 && checkHeight >= 240) {
        finalRes = '426x240';
      } else {
        finalRes = '256x144';
      }
    }

    var finalPreset = selectedPreset;
    if (videoBitrateKbps < 300) finalPreset = SpeedPreset.veryfast;

    return EncodingPlan(
      resolutionText: finalRes,
      fps: selectedFps,
      speed: finalPreset,
      videoBitrateKbps: videoBitrateKbps,
      audioBitrateKbps: (audioBitrateBps / 1000).round(),
    );
  }

  static Future<void> ensureFfmpegAsync({
    void Function(double percent, String eta)? onProgress,
    required CancellationToken token,
  }) async {
    final localFfmpeg = _getFfmpegPath();
    final ffmpegFile = File(localFfmpeg);
    if (await ffmpegFile.exists()) return;

    if (!Platform.isWindows) {
      CompressLogger().warning(
          'Авто-скачивание FFmpeg поддерживается только на Windows.');

      return;
    }

    CompressLogger().process(
        'FFmpeg не найден. Скачивание (~100 МБ)...');

    final zipPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}ffmpeg_temp.zip';

    const url =
        'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip';

    try {
      final request = await _httpClient.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception(
            'Ошибка скачивания FFmpeg: HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength;
      final file = File(zipPath);
      final sink = file.openWrite();

      int totalRead = 0;
      final startTime = DateTime.now();

      await for (final chunk in response) {
        token.throwIfCancelled();
        sink.add(chunk);
        totalRead += chunk.length;

        if (totalBytes > 0 && onProgress != null) {
          final percent = totalRead / totalBytes * 100;
          final elapsed = DateTime.now().difference(startTime).inMilliseconds / 1000;
          final speedBps = elapsed > 0 ? totalRead / elapsed : 0.0;
          final speedText = speedBps >= 1_048_576
              ? '${(speedBps / 1_048_576).toStringAsFixed(1)} MB/s'
              : '${(speedBps / 1024).toStringAsFixed(0)} KB/s';
          final totalEst = elapsed / (percent / 100);
          final etaSec = (totalEst - elapsed).round().clamp(0, 999999);
          final eta = Duration(seconds: etaSec);
          final etaStr =
              '${eta.inMinutes.toString().padLeft(2, '0')}:${(eta.inSeconds % 60).toString().padLeft(2, '0')}';
          onProgress(percent, 'Осталось: $etaStr, $speedText');
        }
      }

      await sink.flush();
      await sink.close();

      CompressLogger().process('Скачивание завершено. Распаковка...');
      onProgress?.call(100, 'Распаковка...');

      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      var found = false;
      for (final entry in archive) {
        if (entry.isFile &&
            p.basename(entry.name).toLowerCase() == 'ffmpeg.exe') {
          final outFile = File(localFfmpeg);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);
          found = true;
          break;
        }
      }

      if (!found) {
        throw Exception('ffmpeg.exe не найден в скачанном архиве.');
      }

      CompressLogger().success('FFmpeg установлен.');
    } finally {
      try {
        await File(zipPath).delete();
      } catch (_) {}
    }
  }

  static Future<void> extractVideoFrameAsync({
    required String inputPath,
    required String outputPath,
    required int frameNumber,
    required CancellationToken token,
  }) async {
    final ffmpegPath = _getFfmpegPath();
    final args = ['-y', '-ss', '1', '-i', inputPath, '-vframes', '1',
        outputPath];

    final result = await Process.run(ffmpegPath, args);
    if (result.exitCode != 0) {
      throw Exception('Failed to extract frame: ${result.stderr}');
    }
  }

  static Future<VideoMetadata> getVideoMetadataAsync({
    required String inputPath,
    required CancellationToken token,
  }) async {
    final ffmpegPath = _getFfmpegPath();
    final result = await Process.run(ffmpegPath, ['-i', inputPath],
        runInShell: false);

    final stderr = result.stderr as String;
    final meta = VideoMetadata();

    final durMatch =
        RegExp(r'Duration:\s*(\d{2}:\d{2}:\d{2}\.\d{2})').firstMatch(stderr);
    if (durMatch != null) {
      final parts = durMatch.group(1)!.split(RegExp(r'[:.]'));
      if (parts.length >= 4) {
        meta.duration = Duration(
          hours: int.parse(parts[0]),
          minutes: int.parse(parts[1]),
          seconds: int.parse(parts[2]),
          milliseconds: int.parse(parts[3]) * 10,
        );
      }
    }

    final resMatch =
        RegExp(r'Stream.*Video:.*?(\d{3,5})x(\d{3,5})').firstMatch(stderr);
    if (resMatch != null) {
      meta.width = int.tryParse(resMatch.group(1) ?? '') ?? 0;
      meta.height = int.tryParse(resMatch.group(2) ?? '') ?? 0;
    }

    final fpsMatch =
        RegExp(r'Video:.*?(\d+(?:\.\d+)?)\s*fps').firstMatch(stderr);
    if (fpsMatch != null) {
      meta.fps = double.tryParse(fpsMatch.group(1) ?? '') ?? 0;
    }

    return meta;
  }

  static Future<void> compressVideoAsync({
    required String inputPath,
    required String outputPath,
    required double targetSizeMb,
    required Duration duration,
    required int originalHeight,
    required VideoCodec codec,
    required SpeedPreset preset,
    required String resolutionPreset,
    required int fpsPreset,
    required AudioCodec audioCodec,
    required AudioVolume audioVolume,
    required bool optimizeWeb,
    required CancellationToken token,
    required void Function(double percent, String eta) onProgress,
  }) async {
    CompressLogger().process('Сжатие видео...');

    final ffmpegPath = _getFfmpegPath();

    final plan = calculateEncodingPlan(
      targetSizeMb: targetSizeMb,
      duration: duration,
      originalHeight: originalHeight,
      selectedRes: resolutionPreset,
      selectedFps: fpsPreset,
      selectedPreset: preset,
      selectedAudio: audioCodec,
    );

    CompressLogger()
        .debug('[Encoder] Оценочный битрейт: ${plan.videoBitrateKbps} kbps');

    final args = <String>[
      '-y',
      '-i', inputPath,
      '-map', '0:v:0',
      '-map', '0:a?',
    ];

    final resMatch = RegExp(r'^(\d+)\s*x\s*(\d+)$', caseSensitive: false)
        .firstMatch(plan.resolutionText);
    if (resMatch != null) {
      int w = int.parse(resMatch.group(1)!);
      int h = int.parse(resMatch.group(2)!);
      if (w % 2 != 0) w++;
      if (h % 2 != 0) h++;
      args.addAll(['-vf', 'scale=$w:$h:flags=lanczos']);
    }

    args.addAll(['-r', plan.fps.toString(), '-fps_mode', 'cfr']);

    switch (codec) {
      case VideoCodec.h265:
        args.addAll(['-c:v', 'libx265']);
      case VideoCodec.av1:
        args.addAll(['-c:v', 'libsvtav1']);
      case VideoCodec.h264:
        args.addAll(['-c:v', 'libx264']);
    }

    final mappedPreset = plan.speed.name;
    if (codec == VideoCodec.av1) {
      final av1Preset = switch (plan.speed) {
        SpeedPreset.ultrafast => '12',
        SpeedPreset.veryfast => '10',
        SpeedPreset.slow => '4',
        SpeedPreset.veryslow => '2',
        SpeedPreset.medium => '6',
      };
      args.addAll(['-preset', av1Preset]);
    } else {
      args.addAll(['-preset', mappedPreset]);
    }

    final rateArg = '-b:v ${plan.videoBitrateKbps}k';
    args.addAll(rateArg.split(' '));
    if (codec != VideoCodec.av1) {
      args.addAll(['-maxrate', '${(plan.videoBitrateKbps * 1.5).round()}k']);
      args.addAll(['-bufsize', '${plan.videoBitrateKbps * 2}k']);
    }

    if (audioCodec == AudioCodec.mute) {
      args.add('-an');
    } else if (audioCodec == AudioCodec.copy) {
      args.addAll(['-c:a', 'copy']);
    } else if (audioCodec == AudioCodec.opus) {
      args.addAll(['-c:a', 'libopus', '-b:a', '${plan.audioBitrateKbps}k']);
    } else {
      args.addAll(['-c:a', 'aac', '-b:a', '${plan.audioBitrateKbps}k']);
    }

    if (audioCodec != AudioCodec.mute &&
        audioCodec != AudioCodec.copy &&
        audioVolume != AudioVolume.original) {
      final volVal = switch (audioVolume) {
        AudioVolume.boost3Db => '3dB',
        AudioVolume.boost6Db => '6dB',
        AudioVolume.boost10Db => '10dB',
        AudioVolume.cut3Db => '-3dB',
        AudioVolume.original => '',
      };
      if (volVal.isNotEmpty) {
        args.addAll(['-filter:a', 'volume=$volVal']);
      }
    }

    if (optimizeWeb) {
      args.addAll(['-movflags', '+faststart']);
    }

    args.add(outputPath);

    CompressLogger().debug('[FFmpeg Command]: $ffmpegPath ${args.join(' ')}');

    final process = await Process.start(ffmpegPath, args,
        runInShell: false);

    var totalDuration = duration;
    DateTime? startTime;
    int lastLoggedPercent = 0;
    final errorHistory = Queue<String>();

    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.isEmpty) return;

      errorHistory.add(line);
      if (errorHistory.length > 15) errorHistory.removeFirst();

      CompressLogger().process('[FFmpeg Log] $line');

      if (totalDuration == Duration.zero && line.contains('Duration:')) {
        final match = RegExp(r'Duration:\s*(\d{2}:\d{2}:\d{2}\.\d{2})')
            .firstMatch(line);
        if (match != null) {
          final parts = match.group(1)!.split(RegExp(r'[:.]'));
          if (parts.length >= 4) {
            totalDuration = Duration(
              hours: int.parse(parts[0]),
              minutes: int.parse(parts[1]),
              seconds: int.parse(parts[2]),
              milliseconds: int.parse(parts[3]) * 10,
            );
          }
        }
      }

      if (totalDuration != Duration.zero && line.contains('time=')) {
        final match =
            RegExp(r'time=\s*(\d{2}:\d{2}:\d{2}\.\d{2})').firstMatch(line);
        if (match != null) {
          final parts = match.group(1)!.split(RegExp(r'[:.]'));
          if (parts.length >= 4) {
            final currentTime = Duration(
              hours: int.parse(parts[0]),
              minutes: int.parse(parts[1]),
              seconds: int.parse(parts[2]),
              milliseconds: int.parse(parts[3]) * 10,
            );

            startTime ??= DateTime.now();

            final percent = currentTime.inMilliseconds /
                totalDuration.inMilliseconds;
            if (percent > 0 && percent <= 1) {
              final currentPercentDouble = percent * 100;
              final elapsed =
                  DateTime.now().difference(startTime!).inSeconds;
              final totalEstSeconds = elapsed / percent;
              final etaSeconds =
                  (totalEstSeconds - elapsed).round().clamp(0, 999999);
              final eta = Duration(seconds: etaSeconds);
              final etaStr =
                  '${eta.inMinutes.toString().padLeft(2, '0')}:${(eta.inSeconds % 60).toString().padLeft(2, '0')}';

              onProgress(currentPercentDouble, 'Осталось: $etaStr');

              final currentPercentInt = currentPercentDouble.round();
              if (currentPercentInt >= lastLoggedPercent + 5) {
                CompressLogger()
                    .process('Прогресс: $currentPercentInt% | $etaStr');
                lastLoggedPercent = currentPercentInt;
              }
            }
          }
        }
      }
    });

    token.throwIfCancelled();

    token.setOnCancel(() {
      try {
        if (!process.kill()) {
          process.kill(ProcessSignal.sigkill);
        }
      } catch (_) {}
    });

    try {
      final exitCode = await process.exitCode;
      token.throwIfCancelled();

      if (exitCode != 0) {
        final detailErr = errorHistory.join('\n');
        throw Exception(
            'FFmpeg ошибка (Код $exitCode).\nПоследние логи:\n$detailErr');
      }

      CompressLogger().success('Сжатие видео завершено.');
    } finally {
      token.clearOnCancel();
    }
  }

  static void openFile(String path) {
    if (!File(path).existsSync()) return;
    if (Platform.isWindows) {
      Process.run('explorer', [path]);
    } else {
      Process.run('xdg-open', [path]);
    }
  }

  static void openFolder(String path) {
    if (!File(path).existsSync()) return;
    if (Platform.isWindows) {
      Process.run('explorer', ['/select,', path]);
    } else {
      Process.run('xdg-open', [p.dirname(path)]);
    }
  }

  static Future<bool> isFfmpegAvailable() async {
    final path = _getFfmpegPath();
    return File(path).exists();
  }

  static String _getFfmpegPath() {
    final appData = Platform.environment['APPDATA'] ?? '';
    final dir = p.join(appData, 'compress');
    return p.join(dir, Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg');
  }

  static Future<String> getFfmpegPath() async => _getFfmpegPath();
}
