import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/audio_analysis.dart';
import '../services/metadata.dart';

class EnergyArtwork extends StatefulWidget {
  const EnergyArtwork({
    super.key,
    required this.track,
    required this.size,
    required this.shape,
    required this.type,
    required this.layers,
    required this.player,
    required this.analysis,
    required this.spectral,
    required this.sensitivity,
  });

  final LocalTrack track;
  final double size;
  final ArtworkShape shape;
  final VisualizerType type;
  final VisualizerLayers layers;
  final AudioPlayer player;
  final AudioAnalysis? analysis;

  /// Multiplicador global de amplitud elegido por el usuario (spec 9).
  final double sensitivity;

  /// Bandas espectrales de la pista (null mientras se analiza).
  final SpectralAudio? spectral;

  @override
  State<EnergyArtwork> createState() => _EnergyArtworkState();
}

class _EnergyArtworkState extends State<EnergyArtwork>
    with WidgetsBindingObserver {
  /// Pico lento por banda para el AGC: sube al instante, decae despacio.
  List<double> _peaks = const [];

  /// Nivel final por banda (AGC + envelope follower), 0–1.
  List<double> _levels = const [];

  /// Energía promedio del tick anterior, para detectar golpes.
  double _lastEnergy = 0.0;

  /// Último frame construido: se reutiliza al limitar a 30fps y al
  /// congelar en pausa / app en background.
  Widget? _cachedFrame;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

  /// Congelado total mientras la app está en background (spec 8).
  bool _lifecyclePaused = false;

  /// Detector de breakdown (spec 4.3): silencio sostenido → modo calmado.
  int _quietTicks = 0;
  bool _breakdown = false;

  /// Cap de 30fps: imperceptible para este contenido, mitad de trabajo.
  static const _frameInterval = Duration(milliseconds: 33);

  /// Decaimiento del pico por tick (~medio minuto en caer del todo).
  static const _peakDecay = 0.998;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecyclePaused = state == AppLifecycleState.paused;
  }

  /// Envolvente por tipo de banda (spec 4.1): graves pegajosos (attack
  /// rápido, release lento y contundente), medios equilibrados, agudos
  /// nerviosos (attack y release rápidos).
  (double attack, double release) _envelopeFor(int index, int count) {
    final t = index / count;
    if (t < 0.25) return (0.5, 0.06); // sub-bass / kick
    if (t < 0.6) return (0.6, 0.10); // snare / medios
    return (0.7, 0.16); // lead / agudos
  }

  /// Normaliza las bandas para que TODAS reaccionen de forma comparable:
  /// 1) AGC por banda: cada banda aprende su propio pico y se expande; así
  ///    los agudos (bandas flojas) no quedan planos y los graves fuertes no
  ///    viven clavados en el máximo.
  /// 2) Envelope follower por banda: ataque rápido, caída lenta.
  /// El State persiste entre ticks del StreamBuilder.
  List<double> _normalizeBands(List<double> bands) {
    if (bands.isEmpty) return const [];
    if (_peaks.length != bands.length) {
      _peaks = List<double>.filled(bands.length, 0.0);
      _levels = List<double>.filled(bands.length, 0.0);
    }
    for (var i = 0; i < bands.length; i++) {
      final band = bands[i].clamp(0.0, 1.0).toDouble();
      final peak = band > _peaks[i] ? band : _peaks[i] * _peakDecay;
      _peaks[i] = peak;
      // Piso mínimo: no amplificar silencio total hasta parpadear.
      final gain = 1.0 / (peak < 0.08 ? 0.08 : peak);
      final target =
          (band * gain * widget.sensitivity).clamp(0.0, 1.0).toDouble();
      final (attack, release) = _envelopeFor(i, bands.length);
      final level = _levels[i];
      _levels[i] = target > level
          ? level + (target - level) * attack
          : level + (target - level) * release;
    }
    return _levels;
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: widget.player.positionStream,
    builder: (context, snapshot) {
      final cached = _cachedFrame;
      // Congelado total (spec 8): app en background o reproducción pausada.
      if (cached != null && (_lifecyclePaused || !widget.player.playing)) {
        return cached;
      }
      // Cap de 30fps: reutiliza el último frame entre ticks.
      final now = DateTime.now();
      if (cached != null && now.difference(_lastFrame) < _frameInterval) {
        return cached;
      }
      _lastFrame = now;
      final position = snapshot.data ?? Duration.zero;
      // Con análisis espectral disponible, la energía se divide por rangos de
      // frecuencia (graves / medios / agudos) para que cada capa reaccione a
      // su propio rango; si no, se usa la envolvente de energía simple.
      final rawBands = widget.spectral?.bandsAt(position);
      final levels = rawBands == null
          ? const <double>[]
          : _normalizeBands(rawBands);
      double graves = 0.0;
      double medios = 0.0;
      double agudos = 0.0;
      if (levels.isNotEmpty) {
        final n = levels.length;
        final gravesEnd = (n * 0.33).round();
        final mediosEnd = (n * 0.66).round();
        var g = 0.0;
        var m = 0.0;
        var a = 0.0;
        for (var i = 0; i < n; i++) {
          final v = levels[i];
          if (i < gravesEnd) {
            g += v;
          } else if (i < mediosEnd) {m += v;}
          // ignore: curly_braces_in_flow_control_structures
          else a += v;
        }
        graves = g / gravesEnd;
        medios = m / (mediosEnd - gravesEnd);
        agudos = a / (n - mediosEnd);
      }
      final energy = levels.isEmpty
          ? widget.analysis?.energyAt(position) ?? 0.0
          : (graves + medios + agudos) / 3;
      final hit = (energy - _lastEnergy * .85).clamp(0.0, 1.0);
      _lastEnergy = energy;
      // Breakdown: silencio sostenido (~2s de ticks) → modo calmado.
      _quietTicks = energy < 0.12 ? _quietTicks + 1 : 0;
      _breakdown = _quietTicks > 60;
      final artworkChild = Center(
        child: Artwork(
          track: widget.track,
          size: widget.size,
          shape: widget.shape,
        ),
      );
      // Las capas (1 / múltiples) aplican al estilo tentáculos; sectores
      // ya divide el círculo por bandas y usa una sola corona.
      final visualizer = switch (widget.type) {
        VisualizerType.tentacles => CustomPaint(
          isComplex: true,
          willChange: true,
          painter: _TentaclesPainter(
            hit: hit,
            position: position,
            shape: widget.shape,
            bands: levels,
            breakdown: _breakdown,
            layerCount: switch (widget.layers) {
              VisualizerLayers.single => 1,
              VisualizerLayers.multiple => 3,
            },
            graves: graves,
            medios: medios,
            agudos: agudos,
          ),
          child: artworkChild,
        ),
        VisualizerType.sectors => CustomPaint(
          isComplex: true,
          willChange: true,
          painter: _ZonesPainter(
            levels: levels,
            shape: widget.shape,
            position: position,
            breakdown: _breakdown,
          ),
          child: artworkChild,
        ),
      };
      _cachedFrame = SizedBox.square(
        dimension: widget.size * 1.75,
        // Aísla el repintado: los ticks del visualizador no invalidan el
        // resto del árbol (controles, textos, lista de canciones).
        child: RepaintBoundary(child: visualizer),
      );
      return _cachedFrame!;
    },
  );
}

/// Painter del tipo "sectores": mapeo espacial fijo de frecuencia.
/// La banda 0 (graves) parte en la parte inferior y las bandas avanzan en
/// sentido horario hasta los agudos; el sector i SIEMPRE representa la banda
/// i, y su amplitud viene del nivel AGC + envelope follower por banda que
/// calcula _EnergyArtworkState.
class _ZonesPainter extends CustomPainter {
  _ZonesPainter({
    required this.levels,
    required this.shape,
    required this.position,
    required this.breakdown,
  });

  final List<double> levels;
  final ArtworkShape shape;
  final Duration position;

  /// Silencio sostenido: atenúa el color de los sectores.
  final bool breakdown;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final center = size.center(Offset.zero);
    final n = levels.length;
    final time = position.inMilliseconds / 1000;
    final maxLen = size.shortestSide * 0.30;

    // Anillo base sutil que marca el borde de la portada.
    canvas.drawCircle(
      center,
      _shapeOrbitDistance(size, shape, 0),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.006
        ..color = Colors.white.withValues(alpha: 0.10),
    );

    final fill = Paint()..style = PaintingStyle.fill;
    // Path único reutilizado con reset por sector.
    final sectorPath = Path();
    for (var i = 0; i < n; i++) {
      final level = levels[i].clamp(0.0, 1.0);
      final midAngle = -pi / 2 + ((i + 0.5) / n) * 2 * pi;
      // Pequeño hueco entre zonas para que se lean como sectores.
      final a0 = -pi / 2 + (i + 0.09) / n * 2 * pi;
      final a1 = -pi / 2 + (i + 0.91) / n * 2 * pi;
      final inner = _shapeOrbitDistance(size, shape, midAngle);
      final outer = inner + size.shortestSide * 0.02 + level * maxLen;

      fill.color = HSVColor.fromAHSV(
        ((0.35 + level * 0.6) * (breakdown ? 0.7 : 1.0)).clamp(0.0, 1.0),
        (i * 360 / n + time * 6) % 360,
        .85,
        (.6 + level * .4).clamp(0.0, 1.0),
      ).toColor();

      // Sector anular entre el borde de la portada y la amplitud de la zona.
      canvas.drawPath(
        sectorPath
          ..reset()
          ..arcTo(
            Rect.fromCircle(center: center, radius: outer),
            a0,
            a1 - a0,
            true,
          )
          ..arcTo(
            Rect.fromCircle(center: center, radius: inner),
            a1,
            -(a1 - a0),
            false,
          )
          ..close(),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(_ZonesPainter oldDelegate) =>
      !identical(oldDelegate.levels, levels) ||
      oldDelegate.position != position ||
      oldDelegate.shape != shape ||
      oldDelegate.breakdown != breakdown;
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
        : Image.memory(
            track.artwork!,
            fit: BoxFit.cover,
            // Decodifica ya redimensionada al tamaño mostrado: evita bitmaps
            // gigantes (4000px) en memoria para miniaturas de 54px.
            cacheWidth:
                (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(
                      1,
                      1024,
                    ),
          );

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

/// Painter del tipo "tentaculos": el mismo estilo de tentaculos se dibuja
/// en 1 capa ("1 capa") o en 3 capas concentricas desfasadas
/// ("multiples capas"), conservando identica geometria por capa.
class _TentaclesPainter extends CustomPainter {
  _TentaclesPainter({
    required this.hit,
    required this.position,
    required this.shape,
    required this.bands,
    required this.breakdown,
    required this.layerCount,
    this.graves = 0.0,
    this.medios = 0.0,
    this.agudos = 0.0,
  });

  final double hit;
  final Duration position;
  final ArtworkShape shape;

  /// Energía 0–1 por banda de frecuencia en la posición actual. La capa
  /// 0 (graves) usa las primeras bandas, la capa 1 (medios) las centrales
  /// y la capa 2 (agudos) las ultimas; vacío = sin modulación espectral.
  final List<double> bands;

  /// Silencio sostenido: atenúa todo para un look calmado.
  final bool breakdown;

  /// 1 con "1 capa"; 3 con "multiples capas".
  final int layerCount;

  /// Energía de las primeras bandas (graves / sub-bass / kick). Usado por
  /// la capa interior; independiente de los medios y agudos (spec 12.2).
  final double graves;

  /// Energía de las bandas centrales (snare / medios). Usada por la capa
  /// media; reacciona con sus propios parametros de envelope.
  final double medios;

  /// Energía de las bandas altas (leads / agudos). Usada por la capa exterior;
  /// reacciona mas rapido y mas nerviosamente que las demas.
  final double agudos;

  /// Configuracion por capa: desfase temporal (phase), radio extra (orbit),
  /// rotacion (spin), escala del largo (scale) y opacidad relativa (alpha).
  /// La capa 0 replica exactamente el estilo de "1 capa"; las demas se
  /// dibujan igual pero desfasadas, mas afuera y con menos opacidad.
  static const _layers = [
    (phase: 0.0, orbit: 0.0, spin: 0.0, scale: 1.0, alpha: 1.0),
    (phase: 0.85, orbit: 0.05, spin: 0.14, scale: 1.22, alpha: 0.55),
    (phase: 1.65, orbit: 0.1, spin: 0.28, scale: 1.44, alpha: 0.35),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .30;
    final time = position.inMilliseconds / 1000;
    final tentacleCount = 32;
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // Un único Path reutilizado (reset por tentáculo): evita crear
    // 32×capas Paths y listas de Offset por frame.
    final tentaclePath = Path();

    for (final (layerIndex, layer) in _layers.take(layerCount).indexed) {
      final layerTime = time + layer.phase;
      // Cada capa reacciona a su propio rango de frecuencias (spec 12.2):
      // capa 0 (graves), capa 1 (medios), capa 2 (agudos).
      final layerEnergy = switch (layerIndex) {
        0 => graves,
        1 => medios,
        _ => agudos,
      };
      for (var i = 0; i < tentacleCount; i++) {
        final angle = i * 2 * pi / tentacleCount + layer.spin;
        final seed = sin(i * 12.9898) * 43758.5453;
        final phase = (seed - seed.floor()) * 2 * pi;
        final organicMotion = sin(layerTime * (1.3 + (i % 5) * .08) + phase);
        final impact = (hit * (0.65 + (i % 4) * .12)).clamp(0.0, 1.0);
        // Modulación espectral: cada tentáculo responde a su banda.
        final band = bands.isEmpty ? 1.0 : bands[i % bands.length];
        final length =
            size.shortestSide *
            layer.scale *
            (0.55 + 0.9 * band) *
            (.025 +
                layerEnergy * (.07 + (i % 3) * .012) +
                impact * (.23 + (i % 5) * .018) +
                organicMotion.abs() * .018);
        // El ángulo es constante por tentáculo: orbit/direction fuera del
        // bucle de puntos.
        final orbit = _shapeOrbitDistance(size, shape, angle);
        final base = orbit + size.shortestSide * (.025 + layer.orbit);
        final direction = Offset(cos(angle), sin(angle));
        tentaclePath
          ..reset()
          ..moveTo(
            center.dx + direction.dx * base,
            center.dy + direction.dy * base,
          );
        for (var point = 1; point <= 8; point++) {
          final t = point / 8;
          final bend =
              sin(phase + t * pi * 1.5 + layerTime * 1.7) *
              size.shortestSide *
              (.012 + impact * .035) *
              t;
          final distance = base + length * t;
          tentaclePath.lineTo(
            center.dx + direction.dx * distance - direction.dy * bend,
            center.dy + direction.dy * distance + direction.dx * bend,
          );
        }

        wavePaint
          ..strokeWidth = size.shortestSide * (.009 + impact * .009)
          ..color = HSVColor.fromAHSV(
            ((.55 + impact * .4) * layer.alpha * (breakdown ? 0.55 : 1.0))
                .clamp(0.0, 1.0),
            (i * 360 / tentacleCount + layerTime * 12) % 360,
            .9,
            (.7 + layerEnergy * .3).clamp(0.0, 1.0),
          ).toColor();
        canvas.drawPath(tentaclePath, wavePaint);
      }

      // Solo la capa principal dibuja el anillo blanco de golpe.
      if (layerIndex == 0 && hit > .08 && !breakdown) {
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
  }

  @override
  bool shouldRepaint(_TentaclesPainter oldDelegate) =>
      oldDelegate.hit != hit ||
      oldDelegate.position != position ||
      oldDelegate.shape != shape ||
      oldDelegate.layerCount != layerCount ||
      oldDelegate.breakdown != breakdown ||
      !identical(oldDelegate.bands, bands) ||
      oldDelegate.graves != graves ||
      oldDelegate.medios != medios ||
      oldDelegate.agudos != agudos;
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
