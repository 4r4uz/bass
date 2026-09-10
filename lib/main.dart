import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:path_provider/path_provider.dart';

import 'pages/home.dart';
import 'services/app_theme.dart';
import 'services/library_store.dart';
import 'services/metadata.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.bass.audio',
    androidNotificationChannelName: '(B)ASS',
    androidNotificationOngoing: true,
    preloadArtwork: true,
    androidStopForegroundOnPause: true,
  );

  final dir = await getApplicationDocumentsDirectory();
  Hive.init(dir.path);

  final library = LibraryStore();
  final tracks = await library.load();

  final savedPresetId = library.setting<String>(LibraryStore.themePresetKey);
  final savedMode = library.setting<String>(LibraryStore.themeModeKey);
  final preset = AppThemePreset.values.firstWhere(
    (entry) => entry.id == savedPresetId,
    orElse: () => AppThemePreset.purple,
  );
  final themeMode = savedMode == 'light' ? ThemeMode.light : ThemeMode.dark;

  runApp(
    MyApp(
      library: library,
      initialTracks: tracks,
      initialThemeMode: themeMode,
      initialThemePreset: preset,
      initialSelected: library.setting<int>(LibraryStore.selectedIndexKey) ?? 0,
      initialShuffle: library.setting<bool>(LibraryStore.shuffleKey) ?? false,
      initialLoopMode:
          library.setting<int>(LibraryStore.loopKey) ?? LoopMode.off.index,
      initialArtworkShape: ArtworkShape.values.firstWhere(
        (shape) =>
            shape.name == library.setting<String>(LibraryStore.artworkShapeKey),
        orElse: () => ArtworkShape.circle,
      ),
      initialVisualizerType: VisualizerType.values.firstWhere(
        (type) =>
            type.name == library.setting<String>(LibraryStore.visualizerTypeKey),
        orElse: () => VisualizerType.tentacles,
      ),
      initialVisualizerLayers: VisualizerLayers.values.firstWhere(
        (layers) =>
            layers.name ==
            library.setting<String>(LibraryStore.visualizerModeKey),
        orElse: () => VisualizerLayers.single,
      ),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    required this.library,
    required this.initialTracks,
    this.initialThemeMode = ThemeMode.dark,
    this.initialThemePreset = AppThemePreset.purple,
    this.initialSelected = 0,
    this.initialShuffle = false,
    this.initialLoopMode = 0,
    this.initialArtworkShape = ArtworkShape.circle,
    this.initialVisualizerType = VisualizerType.tentacles,
    this.initialVisualizerLayers = VisualizerLayers.single,
  });

  final LibraryStore library;
  final List<LocalTrack> initialTracks;
  final ThemeMode initialThemeMode;
  final AppThemePreset initialThemePreset;
  final int initialSelected;
  final bool initialShuffle;
  final int initialLoopMode;
  final ArtworkShape initialArtworkShape;
  final VisualizerType initialVisualizerType;
  final VisualizerLayers initialVisualizerLayers;

  @override
  State<MyApp> createState() => _BassAppState();
}

class _BassAppState extends State<MyApp> {
  late ThemeMode _themeMode;
  late AppThemePreset _themePreset;

  @override
  void initState() {
    super.initState();
    _themePreset = widget.initialThemePreset;
    _themeMode = widget.initialThemeMode;
  }

  ThemeData _themeFor(Brightness brightness) =>
      AppThemePreset.buildTheme(_themePreset, brightness);

  void _applyTheme(AppThemePreset preset, ThemeMode mode) {
    setState(() {
      _themePreset = preset;
      _themeMode = mode;
    });
    widget.library.saveSetting(LibraryStore.themePresetKey, preset.id);
    widget.library.saveSetting(
      LibraryStore.themeModeKey,
      mode == ThemeMode.dark ? 'dark' : 'light',
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '(B)ASS',
    debugShowCheckedModeBanner: false,
    theme: _themeFor(Brightness.light),
    darkTheme: _themeFor(Brightness.dark),
    themeMode: _themeMode,
    home: Home(
      library: widget.library,
      initialTracks: widget.initialTracks,
      initialSelected: widget.initialSelected,
      initialShuffle: widget.initialShuffle,
      initialLoopMode: widget.initialLoopMode,
      initialArtworkShape: widget.initialArtworkShape,
      initialVisualizerType: widget.initialVisualizerType,
      initialVisualizerLayers: widget.initialVisualizerLayers,
      onThemeChanged: _applyTheme,
    ),
  );
}
