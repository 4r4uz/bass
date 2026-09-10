import 'dart:math';
import 'dart:typed_data';

import 'package:hive/hive.dart';

import '../src/rust/api/energy.dart' as rust;

/// Envolvente de energía de una pista: un valor 0–1 por ventana de ~12 ms.
class AudioAnalysis {
  AudioAnalysis({required this.energy, required this.windowsPerSecond});

  final List<double> energy;
  final double windowsPerSecond;

  /// Decodifica la representación cacheada: u16 con ventanas/seg × 100 en la
  /// cabecera y un byte 0–255 por ventana.
  static AudioAnalysis? tryDecode(Uint8List bytes) {
    if (bytes.length < 3) return null;
    final data = ByteData.sublistView(bytes);
    final wps = data.getUint16(0, Endian.little) / 100;
    if (wps <= 0) return null;
    final energy = [for (var i = 2; i < bytes.length; i++) bytes[i] / 255];
    return AudioAnalysis(energy: energy, windowsPerSecond: wps);
  }

  Uint8List encode() {
    final data = ByteData(2 + energy.length);
    data.setUint16(
      0,
      (windowsPerSecond * 100).round().clamp(0, 65535),
      Endian.little,
    );
    final bytes = data.buffer.asUint8List();
    for (var i = 0; i < energy.length; i++) {
      bytes[2 + i] = (energy[i].clamp(0.0, 1.0) * 255).round();
    }
    return bytes;
  }

  /// Energía en la posición de reproducción indicada.
  double energyAt(Duration position) {
    if (energy.isEmpty) return 0;
    final index = (position.inMilliseconds / 1000 * windowsPerSecond).floor();
    return energy[min(max(index, 0), energy.length - 1)];
  }

  /// Picos agregados en [buckets] franjas para dibujar la forma de onda.
  List<double> peaks({int buckets = 220}) {
    final result = List<double>.filled(buckets, 0);
    if (energy.isEmpty) return result;
    final perBucket = energy.length / buckets;
    for (var i = 0; i < buckets; i++) {
      final start = (i * perBucket).floor();
      final end = min(((i + 1) * perBucket).ceil(), energy.length);
      var max = 0.0;
      for (var j = start; j < end; j++) {
        if (energy[j] > max) max = energy[j];
      }
      result[i] = max;
    }
    return result;
  }
}

/// Carga, analiza y cachea la envolvente de energía de las pistas.
///
/// Cache en memoria (sesión) + en Hive (persistente), cuantizada a 1 byte
/// por ventana: ~25 KB por canción de 5 minutos.
class AudioAnalysisStore {
  static const _boxName = 'audio_analysis';
  final _memory = <String, AudioAnalysis>{};
  Future<Box>? _boxFuture;

  Future<Box> _openBox() => _boxFuture ??= Hive.openBox(_boxName);

  /// Devuelve el análisis de la pista, de caché o analizándola con Rust.
  Future<AudioAnalysis?> get(String path) async {
    final memo = _memory[path];
    if (memo != null) return memo;
    final box = await _openBox();
    final raw = box.get(path);
    if (raw is Uint8List) {
      final cached = AudioAnalysis.tryDecode(raw);
      if (cached != null) {
        _memory[path] = cached;
        return cached;
      }
    }
    try {
      final result = await rust.analyzeEnergy(path: path);
      if (result == null || result.windows.isEmpty) return null;
      final analysis = AudioAnalysis(
        energy: result.windows,
        windowsPerSecond: result.windowsPerSecond,
      );
      _memory[path] = analysis;
      await box.put(path, analysis.encode());
      return analysis;
    } on Exception {
      return null;
    }
  }
}

/// Análisis espectral de una pista: bandas de frecuencia por ventana (~12 ms).
class SpectralAudio {
  SpectralAudio({
    required this.bands,
    required this.numBands,
    required this.windowsPerSecond,
  });

  /// Matriz plana: [banda_0_ventana_0, banda_1_ventana_0, ..., banda_0_ventana_1, ...].
  final List<double> bands;

  /// Número de bandas de frecuencia.
  final int numBands;

  /// Ventanas por segundo (depende del sample rate del archivo).
  final double windowsPerSecond;

  /// Número total de ventanas.
  int get numWindows => bands.isEmpty ? 0 : bands.length ~/ numBands;

  /// Decodifica la representación cacheada:
  /// u16: ventanas/seg × 100, u16: num_bandas, luego valores 0–255.
  static SpectralAudio? tryDecode(Uint8List bytes) {
    if (bytes.length < 4) return null;
    final data = ByteData.sublistView(bytes);
    final wps = data.getUint16(0, Endian.little) / 100;
    final numBands = data.getUint16(2, Endian.little);
    if (wps <= 0 || numBands <= 0) return null;
    final bands = [for (var i = 4; i < bytes.length; i++) bytes[i] / 255];
    return SpectralAudio(
      bands: bands,
      numBands: numBands,
      windowsPerSecond: wps,
    );
  }

  Uint8List encode() {
    final data = ByteData(4 + bands.length);
    data.setUint16(
      0,
      (windowsPerSecond * 100).round().clamp(0, 65535),
      Endian.little,
    );
    data.setUint16(2, numBands.clamp(0, 65535), Endian.little);
    final bytes = data.buffer.asUint8List();
    for (var i = 0; i < bands.length; i++) {
      bytes[4 + i] = (bands[i].clamp(0.0, 1.0) * 255).round();
    }
    return bytes;
  }

  /// Obtiene las bandas en la posición de reproducción indicada.
  List<double> bandsAt(Duration position) {
    if (bands.isEmpty || numBands == 0) return List.filled(numBands, 0);
    final windowIndex = (position.inMilliseconds / 1000 * windowsPerSecond)
        .floor();
    final idx = min(max(windowIndex, 0), numWindows - 1);
    final start = idx * numBands;
    return bands.sublist(start, start + numBands);
  }

  /// Energía promedio de todas las bandas en la posición indicada (envolvente simplificada).
  double energyAt(Duration position) {
    final bandValues = bandsAt(position);
    if (bandValues.isEmpty) return 0;
    return bandValues.reduce((a, b) => a + b) / bandValues.length;
  }
}

/// Carga, analiza y cachea el análisis espectral de las pistas.
///
/// Cache en memoria (sesión) + en Hive (persistente).
class SpectralAudioStore {
  static const _boxName = 'spectral_audio';
  final _memory = <String, SpectralAudio>{};
  Future<Box>? _boxFuture;

  Future<Box> _openBox() => _boxFuture ??= Hive.openBox(_boxName);

  /// Duración de cada fragmento del análisis progresivo (segundos).
  static const _chunkSeconds = 12.0;

  /// Análisis progresivo de la pista.
  ///
  /// Si ya está en caché (memoria o Hive) entrega el resultado completo por
  /// [onPartial] una vez y no vuelve a analizar. Si no, analiza por
  /// fragmentos desde Rust avanzando por el archivo y entrega resultados
  /// parciales en vivo (el visualizador funciona mientras analiza); al
  /// terminar guarda el análisis completo en caché para no repetirlo.
  Future<SpectralAudio?> getProgressive(
    String path,
    void Function(SpectralAudio partial) onPartial,
  ) async {
    final memo = _memory[path];
    if (memo != null) {
      onPartial(memo);
      return memo;
    }
    final box = await _openBox();
    final raw = box.get(path);
    if (raw is Uint8List) {
      final cached = SpectralAudio.tryDecode(raw);
      if (cached != null) {
        _memory[path] = cached;
        onPartial(cached);
        return cached;
      }
    }
    try {
      final accumulated = <double>[];
      double? windowsPerSecond;
      var numBands = 0;
      var start = 0.0;
      while (true) {
        final chunk = await rust.analyzeSpectralChunk(
          path: path,
          startSeconds: start,
          durationSeconds: _chunkSeconds,
        );
        // Fragmento vacío: se llegó al final del archivo (o falló).
        if (chunk == null || chunk.bands.isEmpty) break;
        windowsPerSecond ??= chunk.windowsPerSecond;
        numBands = chunk.numBands;
        accumulated.addAll(chunk.bands);
        onPartial(
          SpectralAudio(
            bands: List.of(accumulated),
            numBands: numBands,
            windowsPerSecond: windowsPerSecond,
          ),
        );
        start += _chunkSeconds;
      }
      if (accumulated.isEmpty) return null;
      final full = SpectralAudio(
        bands: accumulated,
        numBands: numBands,
        windowsPerSecond: windowsPerSecond!,
      );
      _memory[path] = full;
      await box.put(path, full.encode());
      return full;
    } on Exception {
      return null;
    }
  }

  /// Devuelve el análisis espectral de la pista, de caché o analizándolo con Rust.
  Future<SpectralAudio?> get(String path) async {
    final memo = _memory[path];
    if (memo != null) return memo;
    final box = await _openBox();
    final raw = box.get(path);
    if (raw is Uint8List) {
      final cached = SpectralAudio.tryDecode(raw);
      if (cached != null) {
        _memory[path] = cached;
        return cached;
      }
    }
    try {
      final result = await rust.analyzeSpectral(path: path);
      if (result == null || result.bands.isEmpty) return null;
      final analysis = SpectralAudio(
        bands: result.bands,
        numBands: result.numBands,
        windowsPerSecond: result.windowsPerSecond,
      );
      _memory[path] = analysis;
      await box.put(path, analysis.encode());
      return analysis;
    } on Exception {
      return null;
    }
  }
}
