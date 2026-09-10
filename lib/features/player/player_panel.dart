import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../services/audio_analysis.dart';
import '../../services/metadata.dart';
import '../../widgets/artwork.dart';
import '../../widgets/seekbar.dart';

class PlayerPanel extends StatelessWidget {
  const PlayerPanel({
    super.key,
    required this.track,
    required this.player,
    required this.shape,
    required this.visualizerType,
    required this.visualizerLayers,
    required this.onMinimize,
    required this.shuffle,
    required this.loopMode,
    required this.analysis,
    required this.spectral,
    required this.sensitivity,
    this.onPrevious,
    this.onNext,
    this.onToggleShuffle,
    this.onCycleLoop,
  });

  final LocalTrack track;
  final AudioPlayer player;
  final ArtworkShape shape;
  final VisualizerType visualizerType;
  final VisualizerLayers visualizerLayers;
  final VoidCallback onMinimize;
  final bool shuffle;
  final LoopMode loopMode;
  final AudioAnalysis? analysis;
  final SpectralAudio? spectral;

  /// Multiplicador de amplitud para el visualizador.
  final double sensitivity;
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
          onNext?.call();
        } else if (velocity > 300) {
          onPrevious?.call();
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
                        type: visualizerType,
                        layers: visualizerLayers,
                        player: player,
                        analysis: analysis,
                        spectral: spectral,
                        sensitivity: sensitivity,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: Text(
                        track.title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                    Text(
                      track.artist,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
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
