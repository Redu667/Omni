import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/collection.dart';
import '../models/network.dart';
import '../state/app_state.dart';

class CollectionsScreen extends StatelessWidget {
  const CollectionsScreen({super.key});

  Future<void> _promptName(
    BuildContext context, {
    String? initial,
    required ValueChanged<String> onSubmit,
  }) async {
    final controller = TextEditingController(text: initial);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initial == null ? 'New collection' : 'Rename collection'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. AQW',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(initial == null ? 'Create' : 'Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) onSubmit(name);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Collections')),
      body: state.collections.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_outlined,
                        size: 64, color: theme.colorScheme.outline),
                    const SizedBox(height: 16),
                    Text('No collections yet',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'A collection gathers sources from different networks '
                      'under one name — put a subreddit, a hashtag feed and '
                      'an account together, and read them as one timeline.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              children: [
                for (final collection in state.collections)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(collection.name),
                    subtitle: Text(collection.sourceIds.isEmpty
                        ? 'No sources yet'
                        : '${collection.sourceIds.length} of '
                            '${state.sources.length} sources'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (choice) => switch (choice) {
                        'rename' => _promptName(
                            context,
                            initial: collection.name,
                            onSubmit: (n) =>
                                state.renameCollection(collection.id, n),
                          ),
                        'delete' => state.removeCollection(collection.id),
                        _ => null,
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => _CollectionSourcesScreen(id: collection.id),
                    )),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New'),
        onPressed: () =>
            _promptName(context, onSubmit: (n) => state.addCollection(n)),
      ),
    );
  }
}

/// Picks which sources belong to one collection.
class _CollectionSourcesScreen extends StatelessWidget {
  const _CollectionSourcesScreen({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final collection =
        state.collections.where((c) => c.id == id).firstOrNull;

    if (collection == null) {
      // Deleted from another screen while this one was open.
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This collection no longer exists.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(collection.name)),
      body: state.sources.isEmpty
          ? const Center(child: Text('Add some sources first.'))
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Pick the sources that belong in ${collection.name}. '
                    'A source can be in as many collections as you like.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
                for (final source in state.sources)
                  CheckboxListTile(
                    secondary: CircleAvatar(
                      backgroundColor:
                          source.network.color.withValues(alpha: 0.15),
                      child: Icon(source.network.icon,
                          color: source.network.color),
                    ),
                    title: Text(source.displayName),
                    subtitle: Text(source.network.label),
                    value: collection.contains(source.id),
                    onChanged: (v) => state.setCollectionMembership(
                        collection.id, source.id, v ?? false),
                  ),
              ],
            ),
    );
  }
}

/// Bottom sheet for putting one source into collections, reached from the
/// sources list.
Future<void> showCollectionPicker(
    BuildContext context, String sourceId) async {
  final state = context.read<AppState>();

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => Consumer<AppState>(
      builder: (_, live, _) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Collections',
                    style: Theme.of(sheetContext).textTheme.titleMedium),
              ),
            ),
            if (live.collections.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Text(
                    'No collections yet — create one from the sidebar to '
                    'group sources across networks.'),
              )
            else
              for (final Collection collection in live.collections)
                CheckboxListTile(
                  title: Text(collection.name),
                  value: collection.contains(sourceId),
                  onChanged: (v) => state.setCollectionMembership(
                      collection.id, sourceId, v ?? false),
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}
