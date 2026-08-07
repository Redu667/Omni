import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/feed_source.dart';
import '../models/network.dart';
import '../services/feed_discovery.dart';
import '../state/app_state.dart';
import 'add_source_screen.dart';
import 'starter_picks_screen.dart';
import 'twitter_settings_screen.dart';

class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  Future<void> _importOpml(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;

    final List<OpmlFeed> feeds;
    try {
      feeds = parseOpml(utf8.decode(bytes, allowMalformed: true));
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (feeds.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('No feeds found in that file.')));
      return;
    }

    final existingUrls = {
      for (final s in state.sources)
        if (s.network == Network.rss) s.params['url'],
    };
    final base = DateTime.now().microsecondsSinceEpoch;
    final sources = [
      for (final (i, feed) in feeds.indexed)
        if (!existingUrls.contains(feed.url))
          FeedSource(
            id: '${base + i}',
            network: Network.rss,
            displayName: feed.title,
            params: {'url': feed.url},
          ),
    ];
    if (sources.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('All feeds in that file are already added.')));
      return;
    }
    await state.addSources(sources);
    messenger.showSnackBar(
        SnackBar(content: Text('Imported ${sources.length} feeds.')));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sources'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Quick start picks',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StarterPicksScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Import OPML',
            onPressed: () => _importOpml(context),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Twitter (X) access',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TwitterSettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.open_in_new),
            title: const Text('Open originals in Omni'),
            subtitle: const Text(
                'Posts always open natively. This controls where "View '
                'original" goes — Omni\'s built-in browser, or yours.'),
            value: state.openInApp,
            onChanged: state.setOpenInApp,
          ),
          const Divider(height: 1),
          if (state.sources.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No sources yet.')),
            )
          else
            ...[
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
