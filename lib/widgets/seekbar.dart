import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// Formatea `[d]` como `mm:ss`.
String formatDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Barra de progreso con seek.
///
/// Muestra una línea recta con un indicador circular para buscar en la canción.
class SeekBar extends StatelessWidget {
  const SeekBar({super.key, required this.player});

  final AudioPlayer player;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration?>(
    stream: player.durationStream,
    builder: (_, durationSnapshot) {
      final total = durationSnapshot.data ?? player.duration ?? Duration.zero;
      final max = total.inMilliseconds > 0
          ? total.inMilliseconds.toDouble()
          : 1.0;
      return StreamBuilder<Duration>(
        stream: player.positionStream,
        builder: (_, positionSnapshot) {
          final position = positionSnapshot.data ?? Duration.zero;
          final value = position.inMilliseconds.clamp(0.0, max).toDouble();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                  ),
                  child: Slider(
                    value: value,
                    max: max,
                    onChanged: total.inMilliseconds > 0
                        ? (v) => player.seek(Duration(milliseconds: v.round()))
                        : null,
                  ),
                ),
                _DurationLabels(position: position, total: total),
              ],
            ),
          );
        },
      );
    },
  );
}

class _DurationLabels extends StatelessWidget {
  const _DurationLabels({required this.position, required this.total});

  final Duration position;
  final Duration total;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(formatDuration(position), style: style),
        Text(formatDuration(total), style: style),
      ],
    );
  }
}
