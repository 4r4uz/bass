import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../features/home/home_logic.dart';
import '../features/library/library_view.dart';
import '../features/player/player_panel.dart';
import '../features/settings/settings_page.dart';
import '../features/theme/theme_picker_sheet.dart';
import '../services/app_theme.dart';
import '../services/audio_analysis.dart';
import '../services/library_store.dart';
import '../services/metadata.dart';
import '../services/watch_folder.dart';

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
    this.initialVisualizerType = VisualizerType.tentacles,
    this.initialVisualizerLayers = VisualizerLayers.single,
  });

  final LibraryStore library;
  final List<LocalTrack> initialTracks;
  final void Function(AppThemePreset preset, ThemeMode mode) onThemeChanged;
  final int initialSelected;
  final bool initialShuffle;
  final int initialLoopMode;
  final ArtworkShape initialArtworkShape;
  final VisualizerType initialVisualizerType;
  final VisualizerLayers initialVisualizerLayers;

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
  late VisualizerType _visualizerType;
  late VisualizerLayers _visualizerLayers;
  bool _showSettings = false;
  final Random _random = Random();
  bool _loading = false;
  bool _expanded = false;
  bool _dragging = false;
  double _dragOffset = 0;
  final AudioAnalysisStore _analysisStore = AudioAnalysisStore();
  AudioAnalysis? _analysis;
  final SpectralAudioStore _spectralStore = SpectralAudioStore();
  SpectralAudio? _spectral;
  String? _watchFolder;
  FolderWatcher? _folderWatcher;
  double _sensitivity = 1.0;
  final Set<String> _loadingSpectral = {};

  LocalTrack? get _current => _tracks.isEmpty ? null : _tracks[_selected];

  /// Carga (o analiza y cachea) la envolvente de energía de la pista.
  Future<void> _loadAnalysis(LocalTrack track) async {
    final analysis = await _analysisStore.get(track.path);
    if (!mounted || _current?.path != track.path) return;
    setState(() => _analysis = analysis);
  }

  /// Carga (o analiza y cachea) las bandas espectrales de la pista.
  ///
  /// Progresivo: si hay caché se entrega completa; si no, Rust analiza por
  /// fragmentos y el visualizador va recibiendo resultados en vivo.
  Future<void> _loadSpectral(LocalTrack track) async {
    if (!_loadingSpectral.add(track.path)) return;
    try {
      await _spectralStore.getProgressive(track.path, (partial) {
        if (!mounted || _current?.path != track.path) return;
        setState(() => _spectral = partial);
      });
    } finally {
      _loadingSpectral.remove(track.path);
    }
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
    _visualizerType = widget.initialVisualizerType;
    _visualizerLayers = widget.initialVisualizerLayers;
    _loopMode = LoopMode.values.firstWhere(
      (mode) => mode.index == widget.initialLoopMode,
      orElse: () => LoopMode.off,
    );
    _sensitivity = widget.library.setting<double>(
      LibraryStore.sensitivityKey,
    ) ??
    1.0;
    // Carpeta observada: escaneo inicial + observación continua.
    _watchFolder = widget.library.setting<String>(LibraryStore.watchFolderKey);
    if (_watchFolder != null) {
      unawaited(_watchLibraryFolder(_watchFolder!));
    }
    // Avanza según loop/aleatorio cuando la pista termina.
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && mounted) {
        _handleTrackEnded();
      }
    });
    // Precarga la última pista seleccionada sin reproducirla.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_tracks.isNotEmpty && mounted) {
        unawaited(
          _player.setAudioSource(_sourceFor(_tracks[_selected])),
        );
        unawaited(_loadAnalysis(_tracks[_selected]));
        unawaited(_loadSpectral(_tracks[_selected]));
      }
    });
  }

  /// Índice de la siguiente pista según aleatorio y modo de repetición.
  int? _nextIndex() => HomeLogic.nextIndex(
    tracks: _tracks,
    selected: _selected,
    loopMode: _loopMode,
    shuffle: _shuffle,
    random: _random,
  );

  /// Índice de la pista anterior según aleatorio y modo de repetición.
  int? _prevIndex() => HomeLogic.prevIndex(
    tracks: _tracks,
    selected: _selected,
    loopMode: _loopMode,
    shuffle: _shuffle,
    random: _random,
  );

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

  /// Agrega las pistas nuevas de [paths], ignorando las ya presentes.
  Future<void> _addPaths(List<String> paths) async {
    var added = false;
    for (final path in paths) {
      if (_tracks.any((track) => track.path == path)) continue;
      _tracks.add(await readLocalTrack(path));
      added = true;
    }
    if (!added) return;
    await widget.library.save(_tracks);
    if (mounted) setState(() {});
  }

  /// Escanea la carpeta observada, importa su música y queda observándola.
  Future<void> _watchLibraryFolder(String folder) async {
    _folderWatcher?.stop();
    final watcher = FolderWatcher(
      folder: folder,
      onChange: () => _syncWatchFolder(folder),
    );
    _folderWatcher = watcher;
    await _syncWatchFolder(folder);
    watcher.start();
  }

  /// Re-escaneo tras detectar cambios en la carpeta (importa solo lo nuevo).
  Future<void> _syncWatchFolder(String folder) async {
    if (!Directory(folder).existsSync()) return;
    final files = await scanAudioFiles(folder);
    await _addPaths(files);
  }

  /// Elige una carpeta desde ajustes y empieza a observarla.
  Future<void> _pickWatchFolder() async {
    final folder = await FilePicker.getDirectoryPath();
    if (folder == null) return;
    setState(() => _watchFolder = folder);
    await widget.library.saveSetting(LibraryStore.watchFolderKey, folder);
    await _watchLibraryFolder(folder);
  }

  @override
  void dispose() {
    _folderWatcher?.stop();
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
    unawaited(_loadSpectral(_tracks[index]));
    await _player.setAudioSource(_sourceFor(_tracks[index]));
    if (play) await _player.play();
  }

  AudioSource _sourceFor(LocalTrack track) => HomeLogic.sourceFor(track);

  void _showThemePicker() {
    final currentMode = Theme.of(context).brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;
    final currentPreset =
        widget.library.setting<String>(LibraryStore.themePresetKey) ??
        AppThemePreset.purple.id;
    final preset = AppThemePreset.values.firstWhere(
      (entry) => entry.id == currentPreset,
      orElse: () => AppThemePreset.purple,
    );

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ThemePickerSheet(
        currentMode: currentMode,
        currentPreset: preset,
        onThemeSelected: (selectedPreset, selectedMode) {
          widget.onThemeChanged(selectedPreset, selectedMode);
          Navigator.pop(context);
        },
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
          ? SettingsPage(
              shape: _artworkShape,
              visualizerType: _visualizerType,
              visualizerLayers: _visualizerLayers,
              onShapeChanged: (shape) {
                setState(() => _artworkShape = shape);
                widget.library.saveSetting(
                  LibraryStore.artworkShapeKey,
                  shape.name,
                );
              },
              onVisualizerTypeChanged: (type) {
                setState(() => _visualizerType = type);
                widget.library.saveSetting(
                  LibraryStore.visualizerTypeKey,
                  type.name,
                );
              },
              onVisualizerLayersChanged: (layers) {
                setState(() => _visualizerLayers = layers);
                widget.library.saveSetting(
                  LibraryStore.visualizerModeKey,
                  layers.name,
                );
              },
              sensitivity: _sensitivity,
              onSensitivityChanged: (value) {
                setState(() => _sensitivity = value);
                widget.library.saveSetting(LibraryStore.sensitivityKey, value);
              },
              watchFolder: _watchFolder,
              onPickWatchFolder: _pickWatchFolder,
              onThemeChanged: _showThemePicker,
            )
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : _tracks.isEmpty
          ? EmptyLibrary(onAdd: _addTracks)
          : Stack(
              children: [
                // Lista de canciones virtualizada: solo construye los tiles
                // visibles (imprescindible con bibliotecas grandes).
                Positioned.fill(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                    // +1 por la cabecera.
                    itemCount: _tracks.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Column(
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
                          ],
                        );
                      }
                      final i = index - 1;
                      return TrackTile(
                        track: _tracks[i],
                        selected: i == _selected,
                        onTap: () => _openTrack(i),
                        shape: _artworkShape,
                      );
                    },
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
                        visualizerType: _visualizerType,
                        visualizerLayers: _visualizerLayers,
                        sensitivity: _sensitivity,
                        shuffle: _shuffle,
                        loopMode: _loopMode,
                        analysis: _analysis,
                        spectral: _spectral,
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

