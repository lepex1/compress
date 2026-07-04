import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'compress_engine.dart';
import 'compress_logger.dart';

class CompressViewModel extends ChangeNotifier {
  CancellationToken? _cts;

  bool _isSyncingResolution = false;

  String? _selectedPath;
  String? _outputPath;
  String _statusSubtext = 'Готов к работе';
  String _processButtonText = 'СЖАТЬ ВИДЕО';
  String _advancedToggleText = 'Расширенные настройки';
  bool _isAdvancedVisible = false;
  bool _ffmpegAvailable = true;
  bool _isDownloadingFfmpeg = false;

  double _targetSizeSliderValue = 25;
  int _targetSizeValue = 25;
  String _targetSizeText = '25';

  final double _sizeSliderMin = 1;
  double _sizeSliderMax = 500;

  double _fpsSliderValue = 30;
  int _fpsValue = 30;
  String _fpsText = '30';
  double _fpsSliderMax = 60;

  int _resolutionIndex = 0;
  String _resolutionWidthText = 'Auto';
  String _resolutionHeightText = 'Auto';
  bool _isCustomResolutionVisible = false;

  bool _is4KEnabled = true;
  bool _is2KEnabled = true;
  bool _is1080pEnabled = true;
  bool _is720pEnabled = true;
  bool _is480pEnabled = true;
  bool _is360pEnabled = true;
  bool _is240pEnabled = true;
  bool _is144pEnabled = true;

  int _videoCodecIndex = 0;
  int _speedPresetIndex = 2;
  int _audioCodecIndex = 0;
  bool _optimizeWeb = true;

  String _autoRecommendationText =
      'Выберите видеофайл для автоматического расчёта параметров.';

  bool _isProcessing = false;
  bool _isFileLoaded = false;
  bool _showPreview = false;
  bool _isResultAvailable = false;

  double _progressPercent = 0;
  String _etaText = 'Анализ файла...';
  String _statusText = 'Готов';

  String _fileName = '';
  String _fileSizeText = '';
  String _fileResolutionText = '';

  Duration _videoDuration = Duration.zero;
  int _videoWidth = 0;
  int _videoHeight = 0;
  double _videoFps = 0;
  Uint8List? _previewBytes;

  String? get selectedPath => _selectedPath;
  String? get outputPath => _outputPath;
  String get statusSubtext => _statusSubtext;
  String get processButtonText => _processButtonText;
  String get advancedToggleText => _advancedToggleText;
  bool get isAdvancedVisible => _isAdvancedVisible;
  bool get ffmpegAvailable => _ffmpegAvailable;
  bool get isDownloadingFfmpeg => _isDownloadingFfmpeg;

  void setFfmpegUnavailable() {
    _ffmpegAvailable = false;
    notifyListeners();
  }

  double get targetSizeSliderValue => _targetSizeSliderValue;
  int get targetSizeValue => _targetSizeValue;
  String get targetSizeText => _targetSizeText;
  double get sizeSliderMin => _sizeSliderMin;
  double get sizeSliderMax => _sizeSliderMax;

  double get fpsSliderValue => _fpsSliderValue;
  int get fpsValue => _fpsValue;
  String get fpsText => _fpsText;
  double get fpsSliderMax => _fpsSliderMax;

  int get resolutionIndex => _resolutionIndex;
  String get resolutionWidthText => _resolutionWidthText;
  String get resolutionHeightText => _resolutionHeightText;
  bool get isCustomResolutionVisible => _isCustomResolutionVisible;

  bool get is4KEnabled => _is4KEnabled;
  bool get is2KEnabled => _is2KEnabled;
  bool get is1080pEnabled => _is1080pEnabled;
  bool get is720pEnabled => _is720pEnabled;
  bool get is480pEnabled => _is480pEnabled;
  bool get is360pEnabled => _is360pEnabled;
  bool get is240pEnabled => _is240pEnabled;
  bool get is144pEnabled => _is144pEnabled;

  int get videoCodecIndex => _videoCodecIndex;
  int get speedPresetIndex => _speedPresetIndex;
  int get audioCodecIndex => _audioCodecIndex;
  bool get optimizeWeb => _optimizeWeb;

  String get autoRecommendationText => _autoRecommendationText;
  bool get isProcessing => _isProcessing;
  bool get isFileLoaded => _isFileLoaded;
  bool get showPreview => _showPreview;
  bool get isResultAvailable => _isResultAvailable;
  double get progressPercent => _progressPercent;
  int get progressPercentRaw => _progressPercent.round();
  String get etaText => _etaText;
  String get statusText => _statusText;
  String get fileName => _fileName;
  String get fileSizeText => _fileSizeText;
  String get fileResolutionText => _fileResolutionText;
  Uint8List? get previewBytes => _previewBytes;

  set selectedPath(String? value) {
    _selectedPath = value;
    notifyListeners();
  }

  set outputPath(String? value) {
    _outputPath = value;
    notifyListeners();
  }

  set isAdvancedVisible(bool value) {
    _isAdvancedVisible = value;
    _advancedToggleText = value ? 'Скрыть настройки' : 'Расширенные настройки';
    notifyListeners();
  }

  set targetSizeSliderValue(double value) {
    _targetSizeSliderValue = value;
    final intVal = value.round().clamp(_sizeSliderMin.round(), _sizeSliderMax.round());
    if (_targetSizeValue != intVal) {
      _targetSizeValue = intVal;
      _targetSizeText = intVal.toString();
      _updateRecommendation();
      _logSizeDebounced(intVal);
    }
    notifyListeners();
  }

  set targetSizeValue(int value) {
    final clamped = value.clamp(_sizeSliderMin.round(), _sizeSliderMax.round());
    if (clamped != value) {
      CompressLogger().warning(
          '[Ограничение] Целевой размер ограничен оригиналом ($_sizeSliderMax МБ) -> установлено $clamped МБ');
    }
    _targetSizeValue = clamped;
    _targetSizeText = clamped.toString();
    if ((_targetSizeSliderValue - clamped).abs() > 0.1) {
      _targetSizeSliderValue = clamped.toDouble();
    }
    _updateRecommendation();
    _logSizeDebounced(clamped);
    notifyListeners();
  }

  set targetSizeText(String value) {
    _targetSizeText = value;
    final parsed = int.tryParse(value);
    if (parsed != null) {
      targetSizeValue = parsed;
    } else {
      notifyListeners();
    }
  }

  set fpsSliderValue(double value) {
    _fpsSliderValue = value;
    final intVal = value.round().clamp(1, max(_fpsSliderMax.round(), 1)).toInt();
    if (_fpsValue != intVal) {
      _fpsValue = intVal;
      _fpsText = intVal.toString();
      _updateRecommendation();
      _logFpsDebounced(intVal);
    }
    notifyListeners();
  }

  set fpsValue(int value) {
    final maxFps = _videoFps > 0 ? _videoFps.round() : 60;
    final clamped = value.clamp(1, maxFps < 1 ? 1 : maxFps);
    if (clamped != value) {
      CompressLogger().warning(
          '[Ограничение] Частота кадров ограничена оригиналом ($maxFps FPS) -> установлено $clamped FPS');
    }
    _fpsValue = clamped;
    _fpsText = clamped.toString();
    if ((_fpsSliderValue - clamped).abs() > 0.1) {
      _fpsSliderValue = clamped.toDouble();
    }
    _updateRecommendation();
    _logFpsDebounced(clamped);
    notifyListeners();
  }

  set fpsText(String value) {
    _fpsText = value;
    final parsed = int.tryParse(value);
    if (parsed != null) {
      fpsValue = parsed;
    } else {
      notifyListeners();
    }
  }

  set resolutionIndex(int value) {
    _resolutionIndex = value;
    _isSyncingResolution = true;
    try {
      _isCustomResolutionVisible = value == 9;
      if (value == 0) {
        _resolutionWidthText = 'Auto';
        _resolutionHeightText = 'Auto';
        _logResolutionDebounced(0, 0);
      } else if (value >= 1 && value <= 8) {
        final (w, h) = _getWidthHeightFromIndex(value);
        _resolutionWidthText = w.toString();
        _resolutionHeightText = h.toString();
        _logResolutionDebounced(w, h);
      }
    } finally {
      _isSyncingResolution = false;
    }
    _updateRecommendation();
    notifyListeners();
  }

  set resolutionWidthText(String value) {
    _resolutionWidthText = value;
    _onResolutionTextChanged();
    notifyListeners();
  }

  set resolutionHeightText(String value) {
    _resolutionHeightText = value;
    _onResolutionTextChanged();
    notifyListeners();
  }

  void _onResolutionTextChanged() {
    if (_isSyncingResolution) return;
    _isSyncingResolution = true;
    try {
      final wText = _resolutionWidthText.trim();
      final hText = _resolutionHeightText.trim();

      if (wText.toLowerCase() == 'auto' || hText.toLowerCase() == 'auto') {
        _resolutionIndex = 0;
        _logResolutionDebounced(0, 0);
      } else {
        final w = int.tryParse(wText);
        final h = int.tryParse(hText);
        if (w != null && h != null) {
          int finalW = w;
          int finalH = h;
          if (_videoWidth > 0 && _videoHeight > 0) {
            if (finalW > _videoWidth || finalH > _videoHeight) {
              final scale = min(_videoWidth / finalW, _videoHeight / finalH);
              finalW = (finalW * scale).round();
              finalH = (finalH * scale).round();
              if (finalW % 2 != 0) finalW++;
              if (finalH % 2 != 0) finalH++;
              _resolutionWidthText = finalW.toString();
              _resolutionHeightText = finalH.toString();
              CompressLogger().warning(
                  '[Ограничение] Разрешение ограничено оригиналом (${_videoWidth}x$_videoHeight) -> установлено ${finalW}x$finalH');
            }
          }
          final presetIdx = _getIndexFromWidthHeight(finalW, finalH);
          _resolutionIndex = presetIdx != -1 ? presetIdx : 9;
          _logResolutionDebounced(finalW, finalH);
        }
      }
    } finally {
      _isSyncingResolution = false;
    }
    _updateRecommendation();
  }

  set videoCodecIndex(int value) {
    _videoCodecIndex = value;
    final codecStr = switch (value) { 1 => 'H.265 (HEVC)', 2 => 'AV1 (SVT-AV1)', _ => 'H.264 (AVC)' };
    CompressLogger().debug('[Параметр] Видеокодек изменён на: $codecStr');
    _updateRecommendation();
    notifyListeners();
  }

  set speedPresetIndex(int value) {
    _speedPresetIndex = value;
    final speedStr = switch (value) {
      0 => 'ultrafast',
      1 => 'veryfast',
      3 => 'slow',
      4 => 'veryslow',
      _ => 'medium'
    };
    CompressLogger().debug('[Параметр] Скорость сжатия изменена на: $speedStr');
    _updateRecommendation();
    notifyListeners();
  }

  set audioCodecIndex(int value) {
    _audioCodecIndex = value;
    final audioStr = switch (value) { 1 => 'Opus', 2 => 'Копировать', 3 => 'Без звука', _ => 'AAC' };
    CompressLogger().debug('[Параметр] Аудиокодек изменён на: $audioStr');
    _updateRecommendation();
    notifyListeners();
  }

  set optimizeWeb(bool value) {
    _optimizeWeb = value;
    CompressLogger().debug('[Параметр] FastStart ${value ? 'включён' : 'выключен'}');
    _updateRecommendation();
    notifyListeners();
  }

  Future<void> loadFileAsync(String path) async {
    if (path.isEmpty || !File(path).existsSync()) return;

    _selectedPath = path;
    _isFileLoaded = true;
    _isResultAvailable = false;

    _fileName = p.basename(path);
    CompressLogger().success('Импортирован видеофайл: $path');

    _videoWidth = 0;
    _videoHeight = 0;
    _videoDuration = Duration.zero;
    _videoFps = 0;
    _previewBytes = null;
    _showPreview = false;

    _statusSubtext = 'Анализ файла...';
    _statusText = 'АНАЛИЗ';
    notifyListeners();

    try {
      final fileInfo = File(path);
      final stat = await fileInfo.stat();
      final originalFileSizeMb = stat.size / (1024 * 1024);
      final maxMb = max(2, originalFileSizeMb.floor());
      _sizeSliderMax = maxMb.toDouble();
      _fileSizeText = '${originalFileSizeMb.toStringAsFixed(1)} MB';

      final meta = await CompressEngine.getVideoMetadataAsync(
          inputPath: path, token: CancellationToken());
      _videoWidth = meta.width;
      _videoHeight = meta.height;
      _videoDuration = meta.duration;
      _videoFps = meta.fps;

      _fileResolutionText =
          '${_videoWidth}x$_videoHeight @ ${_videoFps.toStringAsFixed(0)} FPS';

      CompressLogger().debug(
          '[Анализ] Длительность: ${_videoDuration.toString().substring(0, 7)}, Разрешение: ${_videoWidth}x$_videoHeight, FPS: ${_videoFps.toStringAsFixed(2)}, Вес: ${originalFileSizeMb.toStringAsFixed(2)} MB');

      final checkH = _videoHeight > 0 ? _videoHeight : 99999;
      final checkW = _videoWidth > 0 ? _videoWidth : 99999;
      _is4KEnabled = checkH >= 2160 || checkW >= 3840;
      _is2KEnabled = checkH >= 1440 || checkW >= 2560;
      _is1080pEnabled = checkH >= 1080 || checkW >= 1920;
      _is720pEnabled = checkH >= 720 || checkW >= 1280;
      _is480pEnabled = checkH >= 480 || checkW >= 854;
      _is360pEnabled = checkH >= 360 || checkW >= 640;
      _is240pEnabled = checkH >= 240 || checkW >= 426;
      _is144pEnabled = checkH >= 144 || checkW >= 256;

      final maxFps = _videoFps > 0 ? _videoFps.round() : 60;
      _fpsSliderMax = max(1, maxFps).toDouble();

      _targetSizeValue = min(25, maxMb);
      _targetSizeSliderValue = _targetSizeValue.toDouble();
      _targetSizeText = _targetSizeValue.toString();
      _fpsValue = min(30, maxFps);
      _fpsSliderValue = _fpsValue.toDouble();
      _fpsText = _fpsValue.toString();

      if (await CompressEngine.isFfmpegAvailable()) {
        final tempPreview =
            '${Directory.systemTemp.path}${Platform.pathSeparator}compress_preview_${DateTime.now().millisecondsSinceEpoch}.jpg';
        try {
          await CompressEngine.extractVideoFrameAsync(
              inputPath: path,
              outputPath: tempPreview,
              frameNumber: 2,
              token: CancellationToken());
          final previewFile = File(tempPreview);
          if (await previewFile.exists()) {
            _previewBytes = await previewFile.readAsBytes();
            _showPreview = true;
            try {
              await previewFile.delete();
            } catch (_) {}
          }
        } catch (ex) {
          CompressLogger().warning('Не удалось получить кадр для превью: $ex');
        }
      } else {
        CompressLogger().debug(
            'Превью будет доступно после первого сжатия (требуется FFmpeg)');
      }
    } catch (ex) {
      CompressLogger().error('Ошибка разбора видео: $ex');
    }

    _resolutionIndex = 0;
    _resolutionWidthText = 'Auto';
    _resolutionHeightText = 'Auto';
    _isCustomResolutionVisible = false;

    final ext = p.extension(path);
    _outputPath = p.join(
        p.dirname(path), '${p.basenameWithoutExtension(path)}_optimized$ext');
    _updateStatus('Готов');
    _updateSubtitle('Видео загружено');
    _updateRecommendation();
    notifyListeners();
  }

  void clearFile() {
    _selectedPath = null;
    _outputPath = null;
    _isFileLoaded = false;
    _isResultAvailable = false;
    _showPreview = false;
    _previewBytes = null;
    _fileName = '';
    _fileSizeText = '';
    _fileResolutionText = '';
    _videoWidth = 0;
    _videoHeight = 0;
    _videoDuration = Duration.zero;
    _videoFps = 0;
    _statusSubtext = 'Готов к работе';
    _statusText = 'Готов';
    _autoRecommendationText =
        'Выберите видеофайл для автоматического расчёта параметров.';
    notifyListeners();
  }

  void _updateRecommendation() {
    if (_selectedPath == null || _selectedPath!.isEmpty) {
      _autoRecommendationText =
          'Выберите видеофайл для автоматического расчёта параметров.';
      notifyListeners();
      return;
    }

    if (_videoDuration == Duration.zero) {
      _autoRecommendationText =
          'Не удалось определить параметры видео. Убедитесь, что FFmpeg установлен.';
      notifyListeners();
      return;
    }

    final speed = SpeedPreset.values[_speedPresetIndex];
    final audio = AudioCodec.values[_audioCodecIndex];

    final resolutionParam = _resolutionIndex == 0
        ? 'Auto'
        : '${_resolutionWidthText}x$_resolutionHeightText';

    final plan = CompressEngine.calculateEncodingPlan(
      targetSizeMb: _targetSizeValue.toDouble(),
      duration: _videoDuration,
      originalHeight: _videoHeight,
      selectedRes: resolutionParam,
      selectedFps: _fpsValue,
      selectedPreset: speed,
      selectedAudio: audio,
    );

    final prefix =
        resolutionParam.toLowerCase() == 'auto' ? 'Автонастройка' : 'Принудительно';
    _autoRecommendationText =
        '$prefix: ${plan.resolutionText} @ ${plan.fps} FPS, ~${plan.videoBitrateKbps} kbps, пресет: ${plan.speed.name}';
    notifyListeners();
  }

  Future<void> processMediaAsync() async {
    if (_selectedPath == null ||
        _selectedPath!.isEmpty ||
        _outputPath == null ||
        _outputPath!.isEmpty) {
      return;
    }

    _cts = CancellationToken();
    final token = _cts!;

    _isProcessing = true;
    _isResultAvailable = false;
    _processButtonText = 'СЖАТИЕ...';
    _updateStatus('В ПРОЦЕССЕ');
    _updateSubtitle('Сжатие видео...');
    _etaText = 'Подготовка...';
    _progressPercent = 0;
    notifyListeners();

    try {
      _updateSubtitle('Проверка FFmpeg...');
      notifyListeners();
      await CompressEngine.ensureFfmpegAsync(
        onProgress: (percent, eta) {
          _progressPercent = percent;
          _etaText = eta;
          notifyListeners();
        },
        token: token,
      );

      _progressPercent = 0;
      _updateSubtitle('Обработка...');
      notifyListeners();

      final codec = VideoCodec.values[_videoCodecIndex];
      final speed = SpeedPreset.values[_speedPresetIndex];
      final audio = AudioCodec.values[_audioCodecIndex];

      final resolutionParam = _resolutionIndex == 0
          ? 'Auto'
          : '${_resolutionWidthText}x$_resolutionHeightText';

      await CompressEngine.compressVideoAsync(
        inputPath: _selectedPath!,
        outputPath: _outputPath!,
        targetSizeMb: _targetSizeValue.toDouble(),
        duration: _videoDuration,
        originalHeight: _videoHeight,
        codec: codec,
        preset: speed,
        resolutionPreset: resolutionParam,
        fpsPreset: _fpsValue,
        audioCodec: audio,
        audioVolume: AudioVolume.original,
        optimizeWeb: _optimizeWeb,
        token: token,
        onProgress: (percent, eta) {
          _progressPercent = percent;
          _etaText = eta;
          notifyListeners();
        },
      );

      _updateStatus('ГОТОВО');
      _updateSubtitle('Сжатие завершено');
      _isResultAvailable = true;
      notifyListeners();
    } on CancelledException {
      CompressLogger().warning('Операция отменена пользователем.');
      _updateStatus('ОТМЕНЕНО');
      _cleanFailedOutput();
    } catch (ex) {
      CompressLogger().error('Ошибка выполнения: $ex');
      _updateStatus('ОШИБКА');
      _etaText = 'Сбой: $ex';
      notifyListeners();
    } finally {
      _cts?.clearOnCancel();
      _cts = null;
      _isProcessing = false;
      _processButtonText = 'СЖАТЬ ВИДЕО';
      notifyListeners();
    }
  }

  void cancelProcessing() {
    if (_cts != null && !_cts!.isCancelled) {
      CompressLogger().warning('Пользователь отменил процесс...');
      _cts!.cancel();
    }
  }

  void viewResult() {
    if (_outputPath != null && File(_outputPath!).existsSync()) {
      CompressEngine.openFile(_outputPath!);
    }
  }

  void _cleanFailedOutput() {
    if (_outputPath != null && File(_outputPath!).existsSync()) {
      try {
        File(_outputPath!).delete();
      } catch (_) {}
    }
  }

  Future<void> checkFfmpegAsync() async {
    _ffmpegAvailable = await CompressEngine.isFfmpegAvailable();
    notifyListeners();
  }

  Future<void> downloadFfmpegAsync() async {
    _isDownloadingFfmpeg = true;
    _updateSubtitle('Скачивание FFmpeg...');
    notifyListeners();

    final token = CancellationToken();
    try {
      await CompressEngine.ensureFfmpegAsync(
        onProgress: (percent, eta) {
          _progressPercent = percent;
          _etaText = eta;
          notifyListeners();
        },
        token: token,
      );
      _ffmpegAvailable = true;
      _updateSubtitle('FFmpeg установлен');
    } catch (ex) {
      CompressLogger().error('Ошибка скачивания FFmpeg: $ex');
      rethrow;
    } finally {
      _isDownloadingFfmpeg = false;
      _progressPercent = 0;
      notifyListeners();
    }
  }

  void _updateStatus(String text) {
    _statusText = text;
    notifyListeners();
  }

  void _updateSubtitle(String text) {
    _statusSubtext = text;
    notifyListeners();
  }

  void _logSizeDebounced(int val) {
    CompressLogger().debug('Целевой размер: $val МБ');
  }

  void _logFpsDebounced(int fps) {
    CompressLogger().debug('FPS: $fps');
  }

  void _logResolutionDebounced(int w, int h) {
    if (w == 0 && h == 0) {
      CompressLogger().debug('Разрешение: Auto');
    } else {
      CompressLogger().debug('Разрешение: ${w}x$h');
    }
  }

  (int, int) _getWidthHeightFromIndex(int index) => switch (index) {
        1 => (3840, 2160),
        2 => (2560, 1440),
        3 => (1920, 1080),
        4 => (1280, 720),
        5 => (854, 480),
        6 => (640, 360),
        7 => (426, 240),
        8 => (256, 144),
        _ => (0, 0)
      };

  int _getIndexFromWidthHeight(int w, int h) {
    if (w == 3840 && h == 2160) return 1;
    if (w == 2560 && h == 1440) return 2;
    if (w == 1920 && h == 1080) return 3;
    if (w == 1280 && h == 720) return 4;
    if (w == 854 && h == 480) return 5;
    if (w == 640 && h == 360) return 6;
    if (w == 426 && h == 240) return 7;
    if (w == 256 && h == 144) return 8;
    return -1;
  }
}
