import 'package:flutter/material.dart';

import '../../services/app_theme.dart';

class ThemePickerSheet extends StatelessWidget {
  const ThemePickerSheet({
    super.key,
    required this.currentMode,
    required this.currentPreset,
    required this.onThemeSelected,
  });

  final ThemeMode currentMode;
  final AppThemePreset currentPreset;
  final void Function(AppThemePreset preset, ThemeMode mode) onThemeSelected;

  @override
  Widget build(BuildContext context) => Padding(
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
            onThemeSelected(currentPreset, selection.first);
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
            final isActive = currentPreset.id == preset.id;
            final seed = currentMode == ThemeMode.dark
                ? preset.darkSeed
                : preset.lightSeed;
            return InkWell(
              onTap: () => onThemeSelected(preset, currentMode),
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
  );
}
