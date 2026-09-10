import 'dart:async';
import 'dart:io';

/// Extensiones de archivos de audio reconocidas por la biblioteca.
const audioExtensions = {
  '.mp3',
  '.flac',
  '.wav',
  '.ogg',
  '.oga',
  '.opus',
  '.m4a',
  '.aac',
  '.aif',
  '.aiff',
  '.wma',
};

/// true si [path] parece un archivo de audio soportado.
bool isAudioPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return false;
  return audioExtensions.contains(path.substring(dot).toLowerCase());
}

/// Escanea [folder] recursivamente y devuelve las rutas de audio que
/// contiene, ordenadas por ruta.
Future<List<String>> scanAudioFiles(String folder) async {
  final dir = Directory(folder);
  if (!dir.existsSync()) return [];
  final result = <String>[];
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File && isAudioPath(entity.path)) result.add(entity.path);
  }
  return result..sort();
}

/// Observa [folder] (recursivo, inotify en Android/Linux) y avisa con
/// debounce cuando cambia su contenido, para importar la música nueva.
class FolderWatcher {
  FolderWatcher({required this.folder, required this.onChange});

  final String folder;
  final void Function() onChange;

  StreamSubscription<FileSystemEvent>? _subscription;
  Timer? _debounce;

  /// Empieza a observar. Cancela cualquier observación previa.
  void start() {
    stop();
    _subscription = Directory(folder).watch(recursive: true).listen(
      (_) => _schedule(),
      onError: (_) {},
      cancelOnError: true,
    );
  }

  /// Muchos archivos llegan de golpe (copiar un álbum): reagrupamos.
  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), onChange);
  }

  void stop() {
    _debounce?.cancel();
    _debounce = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}
