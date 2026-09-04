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
      final painter = mode == VisualizerMode.multiple
          ? _MultiLayerEnergyPainter(
              energy: energy,
              hit: hit,
              position: position,
              shape: shape,
            )
          : _EnergyPainter(
              energy: energy,
              hit: hit,
              position: position,
              shape: shape,
            );
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

    final layers = <Map<String, dynamic>>[
      {
        'count': 10,
        'spread': 0.24,
        'speed': 0.7,
        'color': Colors.cyan,
        'amp': 0.9,
      },
      {
        'count': 14,
        'spread': 0.32,
        'speed': 1.15,
        'color': Colors.purple,
        'amp': 1.2,
      },
      {
        'count': 8,
        'spread': 0.46,
        'speed': 2.0,
        'color': Colors.orange,
        'amp': 1.7,
      },
    ];

    for (var layerIndex = 0; layerIndex < layers.length; layerIndex++) {
      final layer = layers[layerIndex];
      final count = layer['count'] as int;
      final spread = layer['spread'] as double;
      final speed = layer['speed'] as double;
      final color = layer['color'] as Color;
      final amp = layer['amp'] as double;
      final layerGain = (energy * 0.8 + hit * 1.2).clamp(0.0, 1.3);

      for (var i = 0; i < count; i++) {
        final baseAngle = i * (2 * pi / count) + time * (0.14 + layerIndex * 0.18);
        final phase = time * speed + i * 0.8;
        final bounce = sin(phase * 2.1 + baseAngle * 2.3) * (0.8 + hit * 0.9);
        final shapeRadius = _shapeOrbitDistance(size, shape, baseAngle);
        final radius =
            shapeRadius +
            size.shortestSide * (spread + layerIndex * 0.12) +
            bounce * size.shortestSide * (0.05 + layerGain * amp * 0.09);

        final points = <Offset>[];
        for (var step = 0; step <= 12; step++) {
          final t = step / 12;
          final wave =
              sin((t * 3.2 + phase) * pi + baseAngle * 1.4) *
              size.shortestSide *
              (0.016 + hit * 0.04 + energy * 0.05 * (layerIndex + 1));
          final orbit = radius + wave * (0.72 + t * 0.5);
          final skew = sin(baseAngle + phase) * size.shortestSide * 0.02;
          final x = center.dx + cos(baseAngle) * orbit - sin(baseAngle) * (wave * 0.8 + skew);
          final y = center.dy + sin(baseAngle) * orbit + cos(baseAngle) * (wave * 0.8 + skew);
          points.add(Offset(x, y));
        }

        paint
          ..strokeWidth =
              size.shortestSide * (0.006 + hit * 0.03 + layerIndex * 0.002)
          ..color = color.withValues(
            alpha: (0.2 + layerGain * 0.42 + layerIndex * 0.12).clamp(0.0, 1.0),
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
      ..strokeWidth = size.shortestSide * 0.013
      ..color = Colors.white.withValues(alpha: (hit * 0.65).clamp(0.0, 1.0));

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
