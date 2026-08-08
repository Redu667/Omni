import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/feed_source.dart';
import '../models/network.dart';
import '../services/feed_discovery.dart';
import '../state/app_state.dart';
import 'filters_screen.dart';
import 'saved_screen.dart';
import 'sources_screen.dart';
import 'reddit_settings_screen.dart';
import 'twitter_settings_screen.dart';

/// Everything that isn't reading. Settings used to be scattered across the
/// sources list, which left that screen doing two jobs and neither well.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _version = '0.9.0';

  Future<void> _importOpml(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);

    final result =
        await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
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

    final existing = {
      for (final s in state.sources)
        if (s.network == Network.rss) s.params['url'],
    };
    final base = DateTime.now().microsecondsSinceEpoch;
    final sources = [
      for (final (i, feed) in feeds.indexed)
        if (!existing.contains(feed.url))
          FeedSource(
            id: '${base + i}',
            network: Network.rss,
            displayName: feed.title,
            params: {'url': feed.url},
          ),
    ];
    if (sources.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('All feeds in that file are already added.')));
      return;
    }
    await state.addSources(sources);
    messenger.showSnackBar(
        SnackBar(content: Text('Imported ${sources.length} feeds.')));
  }

  Future<void> _exportOpml(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);

    final feeds = [
      for (final s in state.sources)
        if (s.network == Network.rss && s.params['url'] != null)
          OpmlFeed(title: s.displayName, url: s.params['url']!),
    ];
    if (feeds.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('No RSS feeds to export.')));
      return;
    }

    final path = await FilePicker.platform.saveFile(
      fileName: 'omni-subscriptions.opml',
      bytes: utf8.encode(buildOpml(feeds)),
    );
    messenger.showSnackBar(SnackBar(
      content: Text(path == null
          ? 'Export cancelled.'
          : 'Exported ${feeds.length} feeds.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final rssCount =
        state.sources.where((s) => s.network == Network.rss).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader('Feed'),
          ListTile(
            leading: const Icon(Icons.rss_feed),
            title: const Text('Sources'),
            subtitle: Text(state.sources.isEmpty
                ? 'None yet'
                : '${state.sources.length} configured, '
                    '${state.sources.where((s) => s.enabled).length} active'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SourcesScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.filter_alt_outlined),
            title: const Text('Filters'),
            subtitle: Text(state.filters.isEmpty
                ? 'Hide posts by word or account'
                : '${state.filters.mutedWords.length} words, '
                    '${state.filters.mutedAccounts.length} accounts muted'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FiltersScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_border),
            title: const Text('Saved posts'),
            subtitle: Text(state.saved.isEmpty
                ? 'Long-press a post to save it'
                : '${state.saved.length} saved'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SavedScreen()),
            ),
          ),

          _SectionHeader('Appearance'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto, size: 18),
                    label: Text('System')),
                ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode, size: 18),
                    label: Text('Light')),
                ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode, size: 18),
                    label: Text('Dark')),
              ],
              selected: {state.themeMode},
              onSelectionChanged: (s) => state.setThemeMode(s.first),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.palette_outlined),
            title: const Text('Use wallpaper colours'),
            subtitle: const Text(
                'Material You. Takes the palette from your wallpaper on '
                'Android 12 and later; Omni\'s own colours otherwise.'),
            value: state.useDynamicColour,
            onChanged: state.setUseDynamicColour,
          ),

          _SectionHeader('Reading'),
          SwitchListTile(
            secondary: const Icon(Icons.mark_email_read_outlined),
            title: const Text('Hide posts you have read'),
            subtitle: const Text(
                'Off dims them instead of removing them. Opening a post '
                'marks it read.'),
            value: state.hideRead,
            onChanged: state.setHideRead,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.swipe_up_outlined),
            title: const Text('Mark read by scrolling past'),
            subtitle: const Text(
                'Posts that pass the top of the screen count as read. They '
                'stay put until the next refresh, so nothing moves under '
                'your thumb.'),
            value: state.markReadOnScroll,
            onChanged: state.setMarkReadOnScroll,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.open_in_new),
            title: const Text('Open originals in Omni'),
            subtitle: const Text(
                'Posts always open natively. This controls where "View '
                'original" goes — Omni\'s built-in browser, or yours.'),
            value: state.openInApp,
            onChanged: state.setOpenInApp,
          ),

          _SectionHeader('Accounts'),
          ListTile(
            leading: const Icon(Icons.reddit),
            title: const Text('Reddit access'),
            subtitle: const Text(
                'Optional app ID that stops Reddit blocking anonymous '
                'requests'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RedditSettingsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.tag),
            title: const Text('Twitter (X) access'),
            subtitle: Text(state.twitterAccount != null
                ? 'Signed in — timelines are live'
                : 'Not signed in — X serves guests stale timelines'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TwitterSettingsScreen()),
            ),
          ),

          _SectionHeader('Subscriptions'),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Import OPML'),
            subtitle: const Text('Bring feeds from another reader'),
            onTap: () => _importOpml(context),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Export OPML'),
            subtitle: Text(rssCount == 0
                ? 'No RSS feeds to export'
                : 'Save your $rssCount feeds to a file'),
            enabled: rssCount > 0,
            onTap: rssCount > 0 ? () => _exportOpml(context) : null,
          ),

          _SectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Omni'),
            subtitle: const Text('Version $_version'),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Source code'),
            subtitle: const Text('github.com/Redu667/Omni'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => launchUrl(
              Uri.parse('https://github.com/Redu667/Omni'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Text(
              'Omni reads; it never posts. Nothing you do here is sent to any '
              'network beyond fetching the feeds you have configured.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
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
