import 'dart:io';
import 'dart:typed_data';

import 'package:haudiotagger/haudiotagger.dart';

class LocalTrack {
  LocalTrack({
    required this.path,
    required this.title,
    required this.artist,
    this.duration,
    required this.bpm,
    this.bpmReady = false,
    this.artwork,
    this.shape = ArtworkShape.rounded,
  });

  final String path;
  String title;
  String artist;
  Duration? duration;
  int bpm;

  /// `true` cuando `bpm` sale del análisis real del audio (o de la caché).
  bool bpmReady;
  Uint8List? artwork;
  ArtworkShape shape;
}

enum ArtworkShape { circle, rounded, square, diamond, triangle }

enum VisualizerMode { single, multiple }

/// Valor de reserva mientras no se analizó el audio (determinista por archivo).
int _estimatedBpm(int fileSize) => 90 + (fileSize % 80);

LocalTrack _fallbackTrack(
  String path,
  String title,
  int fileSize,
  int? cachedBpm,
) => LocalTrack(
  path: path,
  title: title,
  artist: 'Artista desconocido',
  bpm: cachedBpm ?? _estimatedBpm(fileSize),
  bpmReady: cachedBpm != null,
);

Future<LocalTrack> readLocalTrack(String path, {int? cachedBpm}) async {
  final file = File(path);
  final fallbackTitle = path.split(Platform.pathSeparator).last;
  final size = await file.length();
  try {
    final tag = await Haudiotagger.read(path);
    return LocalTrack(
      path: path,
      title: tag?.title?.trim().isNotEmpty == true
          ? tag!.title!.trim()
          : fallbackTitle,
      artist: tag?.trackArtist?.trim().isNotEmpty == true
          ? tag!.trackArtist!.trim()
          : 'Artista desconocido',
      duration: tag?.duration != null
          ? Duration(microseconds: tag!.duration!)
          : null,
      artwork: tag?.pictures.isNotEmpty == true
          ? tag!.pictures.first.bytes
          : null,
      bpm: cachedBpm ?? _estimatedBpm(size),
      bpmReady: cachedBpm != null,
    );
  } on Exception {
    return _fallbackTrack(path, fallbackTitle, size, cachedBpm);
  }
}
