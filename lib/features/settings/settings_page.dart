import 'package:flutter/material.dart';

import '../../services/metadata.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
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
          runSpacing: 8,
          children: VisualizerMode.values
              .map((value) {
                final label = switch (value) {
                  VisualizerMode.single => '1 capa',
                  VisualizerMode.multiple => 'Múltiples capas',
                  VisualizerMode.lineSingle => 'Líneas 1 capa',
                  VisualizerMode.lineMultiple => 'Líneas múltiples',
                  VisualizerMode.waveformSingle => 'Waveform 1 capa',
                  VisualizerMode.waveformMultiple => 'Waveform múltiples',
                };
                return ChoiceChip(
                  label: Text(label),
                  selected: value == visualizerMode,
                  onSelected: (_) => onVisualizerModeChanged(value),
                );
              })
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
