import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/network.dart';
import '../state/app_state.dart';
import 'add_source_screen.dart';

class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Sources')),
      body: state.sources.isEmpty
          ? const Center(child: Text('No sources yet.'))
          : ListView(
              children: [
                for (final source in state.sources)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          source.network.color.withValues(alpha: 0.15),
                      child: Icon(source.network.icon,
                          color: source.network.color),
                    ),
                    title: Text(source.displayName),
                    subtitle: Text(source.network.label),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: source.enabled,
                          onChanged: (v) => state.toggleSource(source.id, v),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove',
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Remove source?'),
                                content: Text(
                                    '"${source.displayName}" and its saved '
                                    'credentials will be removed.'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: const Text('Remove'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await state.removeSource(source.id);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add source',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddSourceScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}
