import 'package:flutter/material.dart';

import '../../services/metadata.dart';
import '../../widgets/artwork.dart';

class EmptyLibrary extends StatelessWidget {
  const EmptyLibrary({super.key, required this.onAdd, required this.onPickFolder});

  final VoidCallback onAdd;
  final VoidCallback onPickFolder;

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
            'Elige una carpeta y su música se importará sola.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onPickFolder,
            icon: const Icon(Icons.folder_open),
            label: const Text('Abrir carpeta'),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.audiotrack_outlined),
            label: const Text('Añadir música suelta'),
          ),
        ],
      ),
    ),
  );
}

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
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
