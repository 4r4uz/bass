import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/audio_analysis.dart';
import '../services/metadata.dart';
import '../widgets/artwork.dart';
import '../widgets/seekbar.dart';

/// Se muestra superpuesto a la lista; al minimizar desaparece pero la
/// reproducción continúa (el [AudioPlayer] vive por fuera de este widget).
class PlayerPanel extends StatelessWidget {
  const PlayerPanel({
    super.key,
    required this.track,
    required this.player,
    required this.shape,
    required this.visualizerMode,
    required this.onMinimize,
    required this.shuffle,
    required this.loopMode,
    required this.analysis,
    this.onPrevious,
    this.onNext,
    this.onToggleShuffle,
    this.onCycleLoop,
  });

  final LocalTrack track;
  final AudioPlayer player;
  final ArtworkShape shape;
  final VisualizerMode visualizerMode;
  final VoidCallback onMinimize;
  final bool shuffle;
  final LoopMode loopMode;
  final AudioAnalysis? analysis;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onToggleShuffle;
  final VoidCallback? onCycleLoop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -300) {
          onPrevious?.call();
        } else if (velocity > 300) {
          onNext?.call();
        }
      },
      child: Container(
        color: scheme.surface,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onMinimize,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    tooltip: 'Minimizar',
                  ),
                  const Spacer(),
                  Text(
                    'REPRODUCIENDO',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      letterSpacing: 3,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -28),
                      child: EnergyArtwork(
                        track: track,
                        size: 180,
                        shape: shape,
                        mode: visualizerMode,
                        player: player,
                        analysis: analysis,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      track.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      track.artist,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    // Barra de progreso con seek: forma de onda si ya hay
                    // análisis, slider como alternativa.
                    SeekBar(player: player),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: onToggleShuffle,
                          icon: const Icon(Icons.shuffle_rounded),
                          color: shuffle ? scheme.primary : null,
                          tooltip: 'Aleatorio',
                        ),
                        IconButton(
                          onPressed: onPrevious,
                          icon: const Icon(Icons.skip_previous_rounded),
                          iconSize: 34,
                        ),
                        const SizedBox(width: 8),
                        _PlayButton(player: player),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: onNext,
                          icon: const Icon(Icons.skip_next_rounded),
                          iconSize: 34,
                        ),
                        IconButton(
                          onPressed: onCycleLoop,
                          icon: Icon(
                            loopMode == LoopMode.one
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                          ),
                          color: loopMode == LoopMode.off
                              ? null
                              : scheme.primary,
                          tooltip: 'Repetir',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra compacta del reproductor, siempre visible sobre la lista.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.track,
    required this.player,
    required this.shape,
    required this.onExpand,
  });

  final LocalTrack track;
  final AudioPlayer player;
  final ArtworkShape shape;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        child: GestureDetector(
          // Deslizar hacia arriba abre el reproductor completo.
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < -250) onExpand();
          },
          child: InkWell(
            onTap: onExpand,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 46,
                    child: Artwork(track: track, size: 46, shape: shape),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _PlayButton(player: player, iconSize: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.player, this.iconSize = 34});

  final AudioPlayer player;
  final double iconSize;

  @override
  Widget build(BuildContext context) => StreamBuilder<PlayerState>(
    stream: player.playerStateStream,
    builder: (_, snapshot) {
      final playing = snapshot.data?.playing ?? false;
      return IconButton.filled(
        iconSize: iconSize,
        onPressed: () => playing ? player.pause() : player.play(),
        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
      );
    },
  );
}
