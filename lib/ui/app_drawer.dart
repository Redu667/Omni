import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/network.dart';
import '../state/app_state.dart';
import 'collections_screen.dart';
import 'saved_screen.dart';
import 'settings_screen.dart';

/// Primary navigation. Collections and networks would overflow a chip bar
/// once you have more than a couple of each, so they live here instead.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final networks = state.activeNetworks.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    void show({Network? network, String? collectionId}) {
      state.showCollection(collectionId);
      state.setFilter(network);
      Navigator.of(context).pop();
    }

    final onAll = state.activeCollection == null && state.filter == null;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Icon(Icons.dynamic_feed, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Text('Omni', style: theme.textTheme.headlineSmall),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.all_inbox),
              title: const Text('All posts'),
              selected: onAll,
              onTap: () => show(),
            ),

            if (state.collections.isNotEmpty) ...[
              const Divider(),
              _Header('Collections', theme: theme),
              for (final collection in state.collections)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(collection.name),
                  subtitle: Text(collection.sourceIds.isEmpty
                      ? 'No sources yet'
                      : '${collection.sourceIds.length} sources'),
                  selected: state.activeCollection?.id == collection.id,
                  onTap: () => show(collectionId: collection.id),
                ),
            ],

            if (networks.isNotEmpty) ...[
              const Divider(),
              _Header('Networks', theme: theme),
              for (final network in networks)
                ListTile(
                  leading: Icon(network.icon, color: network.color),
                  title: Text(network.label),
                  selected: state.filter == network,
                  onTap: () => show(network: network),
                ),
            ],

            const Divider(),
            ListTile(
              leading: const Icon(Icons.folder_copy_outlined),
              title: const Text('Manage collections'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const CollectionsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_border),
              title: const Text('Saved'),
              trailing: state.saved.isEmpty ? null : Text('${state.saved.length}'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SavedScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()));
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.label, {required this.theme});

  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
