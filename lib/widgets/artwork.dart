import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/audio_analysis.dart';
import '../services/metadata.dart';

class EnergyArtwork extends StatelessWidget {
  const EnergyArtwork({
    super.key,
    required this.track,
    required this.size,
    required this.shape,
    required this.mode,
    required this.player,
    required this.analysis,
  });

  final LocalTrack track;
  final double size;
  final ArtworkShape shape;
  final VisualizerMode mode;
  final AudioPlayer player;
  final AudioAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    return _buildEnergy(context);
  }

  Widget _buildEnergy(BuildContext context) => StreamBuilder<Duration>(
    stream: player.positionStream,
    builder: (context, snapshot) {
      final position = snapshot.data ?? Duration.zero;
      final energy = analysis?.energyAt(position) ?? 0.0;
      final previous =
          analysis?.energyAt(position - const Duration(milliseconds: 120)) ??
          0.0;
      final hit = (energy - previous * .85).clamp(0.0, 1.0);
      final painter = switch (mode) {
        VisualizerMode.single => _EnergyPainter(
          energy: energy,
          hit: hit,
          position: position,
          shape: shape,
        ),
        VisualizerMode.multiple => _MultiLayerEnergyPainter(
          energy: energy,
          hit: hit,
          position: position,
          shape: shape,
        ),
        VisualizerMode.lineSingle => _LineEnergyPainter(
          energy: energy,
          hit: hit,
          position: position,
          shape: shape,
        ),
        VisualizerMode.lineMultiple => _LineMultiLayerEnergyPainter(
          energy: energy,
          hit: hit,
          position: position,
          shape: shape,
        ),
        VisualizerMode.waveformSingle => _WaveformEnergyPainter(
          energy: energy,
          hit: hit,
          position: position,
          shape: shape,
        ),
        VisualizerMode.waveformMultiple => _WaveformMultiLayerEnergyPainter(
          energy: energy,
          hit: hit,
          position: position,
          shape: shape,
        ),
      };
      return SizedBox.square(
        dimension: size * 1.75,
        child: CustomPaint(
          painter: painter,
          child: Center(
            child: Artwork(track: track, size: size, shape: shape),
          ),
        ),
      );
    },
  );
}

/// Portada de una pista, recortada según la forma global elegida.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.track,
    required this.size,
    required this.shape,
  });

  final LocalTrack track;
  final double size;
  final ArtworkShape shape;

  @override
  Widget build(BuildContext context) {
    final image = track.artwork == null
        ? const ColoredBox(color: Colors.black)
        : Image.memory(track.artwork!, fit: BoxFit.cover);

    final shaped = switch (shape) {
      ArtworkShape.circle => ClipOval(
        child: SizedBox.square(dimension: size, child: image),
      ),
      ArtworkShape.triangle => ClipPath(
        clipper: TriangleClipper(),
        child: SizedBox.square(dimension: size, child: image),
      ),
      ArtworkShape.diamond => ClipPath(
        clipper: DiamondClipper(),
        child: SizedBox.square(dimension: size, child: image),
      ),
      ArtworkShape.square => SizedBox.square(dimension: size, child: image),
      ArtworkShape.rounded => ClipRRect(
        borderRadius: BorderRadius.circular(size * .14),
        child: SizedBox.square(dimension: size, child: image),
      ),
    };

    return shaped;
  }
}

class _EnergyPainter extends CustomPainter {
  _EnergyPainter({
    required this.energy,
    required this.hit,
    required this.position,
    required this.shape,
  });

  final double energy;
  final double hit;
  final Duration position;
  final ArtworkShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .30;
    final time = position.inMilliseconds / 1000;
    final tentacleCount = 32;
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < tentacleCount; i++) {
      final angle = i * 2 * pi / tentacleCount;
      final seed = sin(i * 12.9898) * 43758.5453;
      final phase = (seed - seed.floor()) * 2 * pi;
      final organicMotion = sin(time * (1.3 + (i % 5) * .08) + phase);
      final impact = (hit * (0.65 + (i % 4) * .12)).clamp(0.0, 1.0);
      final length =
          size.shortestSide *
          (.025 +
              energy * (.07 + (i % 3) * .012) +
              impact * (.23 + (i % 5) * .018) +
              organicMotion.abs() * .018);
      final points = <Offset>[];
      for (var point = 0; point <= 8; point++) {
        final t = point / 8;
        final bend =
            sin(phase + t * pi * 1.5 + time * 1.7) *
            size.shortestSide *
            (.012 + impact * .035) *
            t;
        final orbit = _shapeOrbitDistance(size, shape, angle);
        final distance = orbit + size.shortestSide * .025 + length * t;
        final direction = Offset(cos(angle), sin(angle));
        points.add(
          center +
              Offset(
                direction.dx * distance - direction.dy * bend,
                direction.dy * distance + direction.dx * bend,
              ),
        );
      }

      wavePaint
        ..strokeWidth = size.shortestSide * (.009 + impact * .009)
        ..color = HSVColor.fromAHSV(
          (.55 + impact * .4).clamp(0.0, 1.0),
          (i * 360 / tentacleCount + time * 12) % 360,
          .9,
          (.7 + energy * .3).clamp(0.0, 1.0),
        ).toColor();
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, wavePaint);
    }

    if (hit > .08) {
      wavePaint
        ..strokeWidth = size.shortestSide * .012
        ..color = Colors.white.withAlpha((hit * 150).round().clamp(0, 200));
      canvas.drawCircle(
        center,
        radius + size.shortestSide * (.07 + hit * .12),
        wavePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_EnergyPainter oldDelegate) =>
      oldDelegate.energy != energy ||
      oldDelegate.hit != hit ||
      oldDelegate.position != position ||
      oldDelegate.shape != shape;
}

class _MultiLayerEnergyPainter extends CustomPainter {
  _MultiLayerEnergyPainter({
    required this.energy,
    required this.hit,
    required this.position,
    required this.shape,
  });

  final double energy;
  final double hit;
  final Duration position;
  final ArtworkShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final time = position.inMilliseconds / 1000;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final colors = [
      const Color(0xFF6EE7FF),
      const Color(0xFF8E7BFF),
      const Color(0xFFB77BFF),
      const Color(0xFFFFB86C),
    ];

    for (var layerIndex = 0; layerIndex < colors.length; layerIndex++) {
      final color = colors[layerIndex];
      final count = 10 + layerIndex * 4;
      final spread = 0.18 + layerIndex * 0.12;
      final speed = 0.5 + layerIndex * 0.35;
      final intensity = (energy * 0.7 + hit * 0.8).clamp(0.0, 1.4);
      final layerMotion = 0.25 + layerIndex * 0.12;

      for (var i = 0; i < count; i++) {
        final baseAngle = i * (2 * pi / count) + time * (0.12 + layerIndex * 0.15);
        final phase = time * speed + i * 0.75;
        final lowFreq = sin(phase * 1.4 + baseAngle) * (0.55 + layerMotion);
        final highFreq = sin(phase * 3.1 + baseAngle * 2.2) * (0.8 + hit * 1.4);
        final motion = lowFreq * 0.7 + highFreq * 0.9;
        final shapeRadius = _shapeOrbitDistance(size, shape, baseAngle);
        final radius =
            shapeRadius +
            size.shortestSide * (spread + layerIndex * 0.08) +
            motion * size.shortestSide * (0.04 + intensity * 0.13);

        final points = <Offset>[];
        for (var step = 0; step <= 12; step++) {
          final t = step / 12;
          final wave =
              sin((t * 2.7 + phase) * pi + baseAngle) *
              size.shortestSide *
              (0.012 + hit * 0.04 + energy * 0.05 * (layerIndex + 1));
          final orbit = radius + wave * (0.75 + t * 0.6);
          final skew = sin(baseAngle + phase) * size.shortestSide * 0.018;
          final x = center.dx + cos(baseAngle) * orbit - sin(baseAngle) * (wave * 0.8 + skew);
          final y = center.dy + sin(baseAngle) * orbit + cos(baseAngle) * (wave * 0.8 + skew);
          points.add(Offset(x, y));
        }

        paint
          ..strokeWidth = size.shortestSide * (0.005 + layerIndex * 0.0015 + hit * 0.015)
          ..color = color.withValues(
            alpha: (0.18 + intensity * 0.45 + layerIndex * 0.12).clamp(0.0, 1.0),
          );

        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (final point in points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, paint);
      }
    }

    final burst = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.015
      ..color = Colors.white.withValues(alpha: (hit * 0.7).clamp(0.0, 1.0));

    if (hit > 0.09) {
      final pulseRadius =
          _shapeOrbitDistance(size, shape, 0) +
          size.shortestSide * (0.08 + hit * 0.2);
      canvas.drawCircle(center, pulseRadius, burst);
    }
  }

  @override
  bool shouldRepaint(_MultiLayerEnergyPainter oldDelegate) =>
      oldDelegate.energy != energy ||
      oldDelegate.hit != hit ||
      oldDelegate.position != position ||
      oldDelegate.shape != shape;
}

class _LineEnergyPainter extends CustomPainter {
  _LineEnergyPainter({
    required this.energy,
    required this.hit,
    required this.position,
    required this.shape,
  });

  final double energy;
  final double hit;
  final Duration position;
  final ArtworkShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final time = position.inMilliseconds / 1000;
    final baseRadius = size.shortestSide * (0.14 + energy * 0.22);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.012
      ..color = const Color(0xFF90F0FF).withValues(alpha: 0.9);

    for (var ray = 0; ray < 18; ray++) {
      final angle = (ray / 18) * 2 * pi + time * 0.22;
      final lineWidth = 0.9 + sin(angle * 4 + time * 2.5) * 0.7;
      final radius = baseRadius + sin(angle * 6 + time * 3.1) * size.shortestSide * 0.18;
      final start = center + Offset(cos(angle), sin(angle)) * (radius * 0.5);
      final end = center + Offset(cos(angle), sin(angle)) * (radius + lineWidth * size.shortestSide * 0.16 + hit * size.shortestSide * 0.26);
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(_LineEnergyPainter oldDelegate) =>
      oldDelegate.energy != energy ||
      oldDelegate.hit != hit ||
      oldDelegate.position != position ||
      oldDelegate.shape != shape;
}

class _LineMultiLayerEnergyPainter extends CustomPainter {
  _LineMultiLayerEnergyPainter({
    required this.energy,
    required this.hit,
    required this.position,
    required this.shape,
  });

  final double energy;
  final double hit;
  final Duration position;
  final ArtworkShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final time = position.inMilliseconds / 1000;
    final layers = [
      (const Color(0xFF6EE7FF), 0.6, 0.35),
      (const Color(0xFF8E7BFF), 0.9, 0.7),
      (const Color(0xFFFFB86C), 1.2, 1.05),
    ];

    for (var layerIndex = 0; layerIndex < layers.length; layerIndex++) {
      final (color, speed, gain) = layers[layerIndex];
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * (0.008 + layerIndex * 0.002)
        ..color = color.withValues(alpha: (0.4 + gain * 0.38).clamp(0.0, 1.0));

      for (var ray = 0; ray < 24; ray++) {
        final angle = (ray / 24) * 2 * pi + time * (0.15 + layerIndex * 0.12);
        final low = sin(angle * (3.4 + layerIndex) + time * speed) * 0.7;
        final high = sin(angle * (8 + layerIndex) + time * (2.8 + layerIndex * 0.6)) * 0.9;
        final amplitude = (energy * 0.6 + hit * 0.8 + low * 0.4 + high * 0.7) * size.shortestSide * 0.12;
        final radius = size.shortestSide * (0.18 + layerIndex * 0.12) + amplitude;
        final start = center + Offset(cos(angle), sin(angle)) * (radius * 0.52);
        final end = center + Offset(cos(angle), sin(angle)) * (radius + size.shortestSide * 0.09 + gain * 18);
        canvas.drawLine(start, end, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_LineMultiLayerEnergyPainter oldDelegate) =>
      oldDelegate.energy != energy ||
      oldDelegate.hit != hit ||
      oldDelegate.position != position ||
      oldDelegate.shape != shape;
}

class _WaveformEnergyPainter extends CustomPainter {
  _WaveformEnergyPainter({
    required this.energy,
    required this.hit,
    required this.position,
    required this.shape,
  });

  final double energy;
  final double hit;
  final Duration position;
  final ArtworkShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final time = position.inMilliseconds / 1000;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.012
      ..color = const Color(0xFF58E2C2).withValues(alpha: 0.92);

    final points = <Offset>[];
    for (var i = 0; i <= 40; i++) {
      final t = i / 40;
      final x = -size.shortestSide * 0.34 + t * size.shortestSide * 0.68;
      final wave = sin((t * 15 + time * 2.5)) * size.shortestSide * (0.05 + energy * 0.12);
      final bump = sin((t * 30 + time * 4.5) + hit * 6) * size.shortestSide * 0.045;
      final y = center.dy + wave + bump;
      points.add(Offset(center.dx + x, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);

    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.008
      ..color = Colors.white.withValues(alpha: (hit * 0.8).clamp(0.0, 1.0));
    canvas.drawCircle(center, size.shortestSide * (0.2 + hit * 0.12), halo);
  }

  @override
  bool shouldRepaint(_WaveformEnergyPainter oldDelegate) =>
      oldDelegate.energy != energy ||
      oldDelegate.hit != hit ||
      oldDelegate.position != position ||
      oldDelegate.shape != shape;
}

class _WaveformMultiLayerEnergyPainter extends CustomPainter {
  _WaveformMultiLayerEnergyPainter({
    required this.energy,
    required this.hit,
    required this.position,
    required this.shape,
  });

  final double energy;
  final double hit;
  final Duration position;
  final ArtworkShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final time = position.inMilliseconds / 1000;
    final layers = [
      (const Color(0xFF7DD3FC), 0.9, 0.11),
      (const Color(0xFFA78BFA), 1.35, 0.19),
      (const Color(0xFFFFB86C), 1.9, 0.28),
    ];

    for (var layerIndex = 0; layerIndex < layers.length; layerIndex++) {
      final (color, speed, lift) = layers[layerIndex];
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * (0.008 + layerIndex * 0.0018)
        ..color = color.withValues(alpha: (0.35 + lift * 0.9).clamp(0.0, 1.0));

      final points = <Offset>[];
      for (var i = 0; i <= 42; i++) {
        final t = i / 42;
        final x = -size.shortestSide * 0.38 + t * size.shortestSide * 0.76;
        final baseWave = sin((t * (18 + layerIndex * 4) + time * speed) * pi) * size.shortestSide * (0.02 + energy * 0.12 + lift * 0.16);
        final accent = sin((t * (30 + layerIndex * 7) + time * (3.3 + layerIndex * 0.7)) * pi) * size.shortestSide * (0.03 + hit * 0.08);
        final y = center.dy + baseWave + accent + layerIndex * 12;
        points.add(Offset(center.dx + x, y));
      }

      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformMultiLayerEnergyPainter oldDelegate) =>
      oldDelegate.energy != energy ||
      oldDelegate.hit != hit ||
      oldDelegate.position != position ||
      oldDelegate.shape != shape;
}

double _shapeOrbitDistance(Size size, ArtworkShape shape, double angle) {
  switch (shape) {
    case ArtworkShape.circle:
    case ArtworkShape.rounded:
      return size.shortestSide * .30;
    case ArtworkShape.square:
      final dir = Offset(cos(angle), sin(angle));
      final absX = dir.dx.abs();
      final absY = dir.dy.abs();
      final scale = (absX > absY ? 1 / absX : 1 / absY).clamp(0.7, 1.45);
      return size.shortestSide * .28 * scale;
    case ArtworkShape.diamond:
      final dir = Offset(cos(angle), sin(angle));
      final sum = (dir.dx.abs() + dir.dy.abs()).clamp(0.7, 1.4);
      return size.shortestSide * .25 / sum;
    case ArtworkShape.triangle:
      final dir = Offset(cos(angle), sin(angle));
      final triDenom = (dir.dx.abs() + dir.dy.abs() * 1.25).clamp(0.8, 1.35);
      return size.shortestSide * .26 / triDenom;
  }
}

class TriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(s.width / 2, 0)
    ..lineTo(s.width, s.height)
    ..lineTo(0, s.height)
    ..close();
  @override
  bool shouldReclip(_) => false;
}

class DiamondClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(s.width / 2, 0)
    ..lineTo(s.width, s.height / 2)
    ..lineTo(s.width / 2, s.height)
    ..lineTo(0, s.height / 2)
    ..close();
  @override
  bool shouldReclip(_) => false;
}
