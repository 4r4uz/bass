import 'package:flutter/material.dart';

import '../../services/metadata.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.shape,
    required this.visualizerType,
    required this.visualizerLayers,
    required this.onShapeChanged,
    required this.onVisualizerTypeChanged,
    required this.onVisualizerLayersChanged,
    required this.sensitivity,
    required this.onSensitivityChanged,
    required this.watchFolder,
    required this.onPickWatchFolder,
    required this.onThemeChanged,
  });

  final ArtworkShape shape;
  final VisualizerType visualizerType;
  final VisualizerLayers visualizerLayers;
  final ValueChanged<ArtworkShape> onShapeChanged;
  final ValueChanged<VisualizerType> onVisualizerTypeChanged;
  final ValueChanged<VisualizerLayers> onVisualizerLayersChanged;

  /// Multiplicador global de amplitud del visualizador (0.5–2.0).
  final double sensitivity;
  final ValueChanged<double> onSensitivityChanged;

  /// Carpeta observada (null = ninguna). Su música se importa sola.
  final String? watchFolder;
  final VoidCallback onPickWatchFolder;
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
        const Text('Tipo de visualizador'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: VisualizerType.values
              .map(
                (value) => ChoiceChip(
                  label: Text(switch (value) {
                    VisualizerType.tentacles => 'Tentáculos',
                    VisualizerType.sectors => 'Sectores',
                  }),
                  selected: value == visualizerType,
                  onSelected: (_) => onVisualizerTypeChanged(value),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 24),
        const Text('Capas'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: VisualizerLayers.values
              .map((value) {
                final label = switch (value) {
                  VisualizerLayers.single => '1 capa',
                  VisualizerLayers.multiple => 'Múltiples capas',
                };
                return ChoiceChip(
                  label: Text(label),
                  selected: value == visualizerLayers,
                  onSelected: (_) => onVisualizerLayersChanged(value),
                );
              })
              .toList(),
        ),
        const SizedBox(height: 24),
        const Text('Sensibilidad del visualizador'),
        Slider(
          value: sensitivity,
          min: 0.5,
          max: 2.0,
          divisions: 15,
          label: sensitivity.toStringAsFixed(1),
          onChanged: onSensitivityChanged,
        ),
        const SizedBox(height: 24),
        const Text('Carpeta observada'),
        const SizedBox(height: 4),
        Text(
          watchFolder ??
              'Ninguna: elige una carpeta y su música se importará sola.',
          style: Theme.of(context).textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: onPickWatchFolder,
          icon: const Icon(Icons.folder_special_outlined),
          label: Text(watchFolder == null ? 'Elegir carpeta' : 'Cambiar carpeta'),
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
