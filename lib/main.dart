import 'dart:async';

import 'package:audio_service/audio_service.dart';
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
    androidNotificationChannelDescription: 'Controles de reproducción de música',
    notificationColor: const Color(0xFFB77BFF),
    androidNotificationIcon: 'mipmap/ic_launcher',
    androidNotificationOngoing: false,
    androidNotificationClickStartsActivity: true,
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
      initialVisualizerMode: VisualizerMode.values.firstWhere(
        (mode) =>
            mode.name ==
            library.setting<String>(LibraryStore.visualizerModeKey),
        orElse: () => VisualizerMode.single,
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
    this.initialVisualizerMode = VisualizerMode.single,
  });

  final LibraryStore library;
  final List<LocalTrack> initialTracks;
  final ThemeMode initialThemeMode;
  final AppThemePreset initialThemePreset;
  final int initialSelected;
  final bool initialShuffle;
  final int initialLoopMode;
  final ArtworkShape initialArtworkShape;
  final VisualizerMode initialVisualizerMode;

  @override
  State<MyApp> createState() => _BassAppState();
}

class _BassAppState extends State<MyApp> with WidgetsBindingObserver {
  late ThemeMode _themeMode;
  late AppThemePreset _themePreset;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _themePreset = widget.initialThemePreset;
    _themeMode = widget.initialThemeMode;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // ignore: deprecated_member_use
      unawaited(AudioService.stop());
    }
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
      initialVisualizerMode: widget.initialVisualizerMode,
      onThemeChanged: _applyTheme,
    ),
  );
}
