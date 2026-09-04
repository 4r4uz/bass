import 'dart:async';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../services/app_theme.dart';
import '../services/audio_analysis.dart';
import '../services/library_store.dart';
import '../services/metadata.dart';
import '../widgets/artwork.dart';
import 'player.dart';

class Home extends StatefulWidget {
  const Home({
    super.key,
    required this.library,
    required this.initialTracks,
    required this.onThemeChanged,
    this.initialSelected = 0,
    this.initialShuffle = false,
    this.initialLoopMode = 0,
    this.initialArtworkShape = ArtworkShape.rounded,
    this.initialVisualizerMode = VisualizerMode.single,
  });

  final LibraryStore library;
  final List<LocalTrack> initialTracks;
  final void Function(AppThemePreset preset, ThemeMode mode) onThemeChanged;
  final int initialSelected;
  final bool initialShuffle;
  final int initialLoopMode;
  final ArtworkShape initialArtworkShape;
  final VisualizerMode initialVisualizerMode;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with TickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  late final List<LocalTrack> _tracks = List.of(widget.initialTracks);
  late int _selected;
  late bool _shuffle;
  late LoopMode _loopMode;
  late ArtworkShape _artworkShape;
  late VisualizerMode _visualizerMode;
  bool _showSettings = false;
  final Random _random = Random();
  bool _loading = false;
  bool _expanded = false;
  bool _dragging = false;
  double _dragOffset = 0;
  final AudioAnalysisStore _analysisStore = AudioAnalysisStore();
  AudioAnalysis? _analysis;

  LocalTrack? get _current => _tracks.isEmpty ? null : _tracks[_selected];

  /// Carga (o analiza y cachea) la envolvente de energía de la pista.
  Future<void> _loadAnalysis(LocalTrack track) async {
    final analysis = await _analysisStore.get(track.path);
    if (!mounted || _current?.path != track.path) return;
    setState(() => _analysis = analysis);
  }

  void _expandPlayer() => setState(() => _expanded = true);

  void _minimizePlayer() => setState(() => _expanded = false);

  /// Reproduce la pista elegida y abre el reproductor en grande.
  Future<void> _openTrack(int index) async {
    await _selectTrack(index);
    if (mounted) _expandPlayer();
  }

  @override
  void initState() {
    super.initState();
    // Si la pista guardada ya no existe, volvemos a la primera.
    _selected =
        widget.initialSelected >= 0 &&
            widget.initialSelected < widget.initialTracks.length
        ? widget.initialSelected
        : 0;
    _shuffle = widget.initialShuffle;
    _artworkShape = widget.initialArtworkShape;
    _visualizerMode = widget.initialVisualizerMode;
    _loopMode = LoopMode.values.firstWhere(
      (mode) => mode.index == widget.initialLoopMode,
      orElse: () => LoopMode.off,
    );
    // Avanza según loop/aleatorio cuando la pista termina.
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && mounted) {
        _handleTrackEnded();
      }
    });
    // Precarga la última pista seleccionada sin reproducirla.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tracks.isNotEmpty && mounted) {
        _player.setAudioSource(_sourceFor(_tracks[_selected]));
        unawaited(_loadAnalysis(_tracks[_selected]));
      }
    });
  }

  /// Índice de la siguiente pista según aleatorio y modo de repetición.
  /// Devuelve `null` cuando no hay siguiente (fin de la lista sin repetir).
  int? _nextIndex() {
    if (_tracks.isEmpty) return null;
    if (_shuffle && _tracks.length > 1) return _randomIndex();
    if (_selected < _tracks.length - 1) return _selected + 1;
    if (_loopMode == LoopMode.all) return 0;
    return null;
  }

  /// Índice de la pista anterior según aleatorio y modo de repetición.
  int? _prevIndex() {
    if (_tracks.isEmpty) return null;
    if (_shuffle && _tracks.length > 1) return _randomIndex();
    if (_selected > 0) return _selected - 1;
    if (_loopMode == LoopMode.all) return _tracks.length - 1;
    return null;
  }

  int _randomIndex() {
    var candidate = _selected;
    while (candidate == _selected) {
      candidate = _random.nextInt(_tracks.length);
    }
    return candidate;
  }

  /// Siguiente pista: reproduce la siguiente según aleatorio/loop.
  Future<void> _seekToNext() async {
    final index = _nextIndex();
    if (index != null) await _selectTrack(index);
  }

  /// Pista anterior: reproduce la anterior según aleatorio/loop.
  Future<void> _seekToPrev() async {
    final index = _prevIndex();
    if (index != null) await _selectTrack(index);
  }

  Future<void> _handleTrackEnded() async {
    if (_loopMode == LoopMode.one) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }
    final next = _nextIndex();
    if (next != null) {
      await _selectTrack(next);
      await _player.play();
    }
  }

  void _toggleShuffle() {
    setState(() => _shuffle = !_shuffle);
    widget.library.saveSetting(LibraryStore.shuffleKey, _shuffle);
  }

  /// Cicla el modo de repetición: off → todas → una → off.
  void _cycleLoop() {
    setState(() {
      _loopMode = switch (_loopMode) {
        LoopMode.off => LoopMode.all,
        LoopMode.all => LoopMode.one,
        LoopMode.one => LoopMode.off,
      };
    });
    widget.library.saveSetting(LibraryStore.loopKey, _loopMode.index);
  }

  /// Arrastre en vivo: el panel sigue el dedo hacia abajo.
  void _onPanelDrag(DragUpdateDetails details, double maxHeight) {
    setState(() {
      _dragging = true;
      _dragOffset = (_dragOffset + (details.primaryDelta ?? 0)).clamp(
        0.0,
        maxHeight,
      );
    });
  }

  /// Al soltar: minimiza si se arrastró lo suficiente o con impulso;
  /// si no, vuelve a abrirse.
  void _onPanelDragEnd(DragEndDetails details, double maxHeight) {
    final velocity = details.primaryVelocity ?? 0;
    final close = _dragOffset > maxHeight * .3 || velocity > 900;
    setState(() {
      _dragging = false;
      _dragOffset = 0;
      _expanded = !close;
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _addTracks() async {
    final result = await FilePicker.pickFiles(type: FileType.audio);
    setState(() => _loading = true);
    for (final picked in result) {
      if (picked.path == null ||
          _tracks.any((track) => track.path == picked.path)) {
        continue;
      }
      final track = await readLocalTrack(picked.path!);
      _tracks.add(track);
    }
    await widget.library.save(_tracks);
    if (mounted) {
      setState(() => _loading = false);
      if (_tracks.isNotEmpty) {
        await _selectTrack(_tracks.length - 1, play: false);
      }
    }
  }

  Future<void> _selectTrack(int index, {bool play = true}) async {
    setState(() => _selected = index);
    widget.library.saveSetting(LibraryStore.selectedIndexKey, index);
    unawaited(_loadAnalysis(_tracks[index]));
    await _player.setAudioSource(_sourceFor(_tracks[index]));
    if (play) await _player.play();
  }

  AudioSource _sourceFor(LocalTrack track) => AudioSource.file(
    track.path,
    tag: MediaItem(
      id: track.path,
      title: track.title,
      album: '(B)ASS',
      artist: track.artist,
      duration: track.duration,
    ),
  );

  void _showThemePicker() {
    final currentMode = Theme.of(context).brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tema de la aplicación',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 18),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.light,
                  label: Text('Claro'),
                  icon: Icon(Icons.light_mode_rounded),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.dark,
                  label: Text('Oscuro'),
                  icon: Icon(Icons.dark_mode_rounded),
                ),
              ],
              selected: {currentMode},
              onSelectionChanged: (selection) {
                final mode = selection.first;
                final preset = AppThemePreset.values.firstWhere(
                  (entry) => entry.id ==
                      (widget.library.setting<String>(LibraryStore.themePresetKey) ??
                          AppThemePreset.purple.id),
                  orElse: () => AppThemePreset.purple,
                );
                widget.onThemeChanged(preset, mode);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'Paleta',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: AppThemePreset.values.map((preset) {
                final isActive =
                    (widget.library.setting<String>(LibraryStore.themePresetKey) ??
                            AppThemePreset.purple.id) ==
                        preset.id;
                final seed = currentMode == ThemeMode.dark
                    ? preset.darkSeed
                    : preset.lightSeed;
                return InkWell(
                  onTap: () {
                    widget.onThemeChanged(preset, currentMode);
                    Navigator.pop(context);
                  },
                  borderRadius: BorderRadius.circular(30),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: seed,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isActive
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '(B)ASS',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 3),
        ),
        actions: [
          if (!_showSettings)
            IconButton(
              onPressed: _addTracks,
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Añadir música',
            ),
          IconButton(
            onPressed: () => setState(() => _showSettings = !_showSettings),
            icon: Icon(_showSettings ? Icons.close : Icons.settings_outlined),
            tooltip: _showSettings ? 'Cerrar ajustes' : 'Ajustes',
          ),
        ],
      ),
      body: _showSettings
          ? _SettingsPage(
              shape: _artworkShape,
              visualizerMode: _visualizerMode,
              onShapeChanged: (shape) {
                setState(() => _artworkShape = shape);
                widget.library.saveSetting(
                  LibraryStore.artworkShapeKey,
                  shape.name,
                );
              },
              onVisualizerModeChanged: (mode) {
                setState(() => _visualizerMode = mode);
                widget.library.saveSetting(
                  LibraryStore.visualizerModeKey,
                  mode.name,
                );
              },
              onThemeChanged: _showThemePicker,
            )
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : _tracks.isEmpty
          ? _EmptyLibrary(onAdd: _addTracks)
          : Stack(
              children: [
                // Lista de canciones.
                Positioned.fill(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Tu biblioteca',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text('${_tracks.length} canciones'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ..._tracks.asMap().entries.map(
                        (entry) => _TrackTile(
                          track: entry.value,
                          selected: entry.key == _selected,
                          onTap: () => _openTrack(entry.key),
                          shape: _artworkShape,
                        ),
                      ),
                    ],
                  ),
                ),
                if (current != null) ...[
                  // Mini reproductor: se oculta deslizándolo fuera de pantalla
                  // cuando el reproductor está en grande.
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    left: 0,
                    right: 0,
                    bottom: _expanded ? -90 : 0,
                    child: MiniPlayer(
                      track: current,
                      player: _player,
                      shape: _artworkShape,
                      onExpand: _expandPlayer,
                    ),
                  ),
                  // Reproductor en grande: sigue el dedo al arrastrar y
                  // anima el resto del camino.
                  AnimatedPositioned(
                    duration: _dragging
                        ? Duration.zero
                        : const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    left: 0,
                    right: 0,
                    top: _expanded ? _dragOffset : screenHeight,
                    height: screenHeight,
                    child: GestureDetector(
                      onVerticalDragUpdate: _expanded
                          ? (details) => _onPanelDrag(details, screenHeight)
                          : null,
                      onVerticalDragEnd: _expanded
                          ? (details) => _onPanelDragEnd(details, screenHeight)
                          : null,
                      child: PlayerPanel(
                        track: current,
                        player: _player,
                        shape: _artworkShape,
                        visualizerMode: _visualizerMode,
                        shuffle: _shuffle,
                        loopMode: _loopMode,
                        analysis: _analysis,
                        onMinimize: _minimizePlayer,
                        onPrevious: _prevIndex() == null ? null : _seekToPrev,
                        onNext: _nextIndex() == null ? null : _seekToNext,
                        onToggleShuffle: _toggleShuffle,
                        onCycleLoop: _cycleLoop,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.graphic_eq_rounded,
            size: 76,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 20),
          const Text(
            'Tu música, a tu manera',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Añade archivos locales y personaliza cada portada.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.folder_open),
            label: const Text('Añadir música'),
          ),
        ],
      ),
    ),
  );
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.selected,
    required this.onTap,
    required this.shape,
  });
  final LocalTrack track;
  final bool selected;
  final VoidCallback onTap;
  final ArtworkShape shape;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: SizedBox.square(
      dimension: 54,
      child: Artwork(track: track, size: 54, shape: shape),
    ),
    title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(track.artist),
    selected: selected,
    onTap: onTap,
  );
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.shape,
    required this.visualizerMode,
    required this.onShapeChanged,
    required this.onVisualizerModeChanged,
    required this.onThemeChanged,
  });

  final ArtworkShape shape;
  final VisualizerMode visualizerMode;
  final ValueChanged<ArtworkShape> onShapeChanged;
  final ValueChanged<VisualizerMode> onVisualizerModeChanged;
  final VoidCallback onThemeChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ajustes globales',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        const Text('Forma de las portadas'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: ArtworkShape.values
              .map(
                (value) => ChoiceChip(
                  label: Text(value.name),
                  selected: value == shape,
                  onSelected: (_) => onShapeChanged(value),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 24),
        const Text('Tipo de visualización'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: VisualizerMode.values
              .map(
                (value) => ChoiceChip(
                  label: Text(
                    value == VisualizerMode.single
                        ? '1 capa'
                        : 'Múltiples capas',
                  ),
                  selected: value == visualizerMode,
                  onSelected: (_) => onVisualizerModeChanged(value),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 24),
        FilledButton.tonalIcon(
          onPressed: onThemeChanged,
          icon: const Icon(Icons.palette_outlined),
          label: const Text('Tema de la aplicación'),
        ),
      ],
    ),
  );
}
