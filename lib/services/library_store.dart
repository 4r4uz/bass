import 'dart:io';

import 'package:hive/hive.dart';

import 'metadata.dart';

/// Solo se guardan las rutas; los metadatos y el artwork se vuelven a leer del
/// archivo al abrir la app.
class LibraryStore {
  static const _boxName = 'library';
  static const _tracksKey = 'tracks';

  static const seedColorKey = 'seedColor';
  static const themeModeKey = 'themeMode';
  static const themePresetKey = 'themePreset';
  static const selectedIndexKey = 'selectedIndex';
  static const visualizerModeKey = 'visualizerMode';
  static const shuffleKey = 'shuffle';
  static const loopKey = 'loop';
  static const artworkShapeKey = 'artworkShape';

  Box? _box;

  /// Lee un valor de configuración guardado (null si no hay).
  T? setting<T>(String key) => _box?.get(key) as T?;

  Future<void> saveSetting(String key, Object? value) async {
    final box = _box;
    if (box == null) return;
    await box.put(key, value);
  }

  Future<List<LocalTrack>> load() async {
    final box = _box = await Hive.openBox(_boxName);
    final raw = box.get(_tracksKey) as List?;
    if (raw == null) return [];
    final tracks = <LocalTrack>[];
    for (final item in raw) {
      final map = Map<String, dynamic>.from(item as Map);
      final path = map['path'] as String?;
      if (path == null || !File(path).existsSync()) continue;
      final track = await readLocalTrack(path, cachedBpm: map['bpm'] as int?);
      tracks.add(track);
    }
    return tracks;
  }

  Future<void> save(List<LocalTrack> tracks) async {
    final box = _box;
    if (box == null) return;
    await box.put(_tracksKey, [
      for (final track in tracks)
        {
          'path': track.path,
          // Solo se cachea el BPM del análisis real del audio.
          'bpm': track.bpmReady ? track.bpm : null,
        },
    ]);
  }
}
