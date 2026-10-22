import 'dart:io';
import 'dart:math';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/metadata.dart';

class HomeLogic {
  const HomeLogic();

  static int? nextIndex({
    required List<LocalTrack> tracks,
    required int selected,
    required LoopMode loopMode,
    required bool shuffle,
    required Random random,
  }) {
    if (tracks.isEmpty) return null;
    if (shuffle && tracks.length > 1) {
      return randomIndex(
        tracks: tracks,
        selected: selected,
        random: random,
      );
    }
    if (selected < tracks.length - 1) return selected + 1;
    if (loopMode == LoopMode.all) return 0;
    return null;
  }

  static int? prevIndex({
    required List<LocalTrack> tracks,
    required int selected,
    required LoopMode loopMode,
    required bool shuffle,
    required Random random,
  }) {
    if (tracks.isEmpty) return null;
    if (shuffle && tracks.length > 1) {
      return randomIndex(
        tracks: tracks,
        selected: selected,
        random: random,
      );
    }
    if (selected > 0) return selected - 1;
    if (loopMode == LoopMode.all) return tracks.length - 1;
    return null;
  }

  static int randomIndex({
    required List<LocalTrack> tracks,
    required int selected,
    required Random random,
  }) {
    if (tracks.length < 2) return selected;
    var candidate = selected;
    while (candidate == selected) {
      candidate = random.nextInt(tracks.length);
    }
    return candidate;
  }

    static Future<AudioSource> sourceFor(LocalTrack track) async {
    Uri? artUri;
    if (track.artwork != null) {
      artUri = await _writeArtworkToTempFile(track);
    }

    return AudioSource.file(
      track.path,
      tag: MediaItem(
        id: track.path,
        title: track.title,
        artist: track.artist,
        duration: track.duration,
        artUri: artUri,
      ),
    );
  }

  static Future<Uri> _writeArtworkToTempFile(LocalTrack track) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/art_${track.path.hashCode}.jpg');
    if (!await file.exists()) {
      await file.writeAsBytes(track.artwork!);
    }
    return file.uri;
  }
}
