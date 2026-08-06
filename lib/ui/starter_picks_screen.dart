import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/feed_source.dart';
import '../models/network.dart';
import '../state/app_state.dart';

class _StarterPick {
  const _StarterPick(this.network, this.title, this.subtitle, this.params);

  final Network network;
  final String title;
  final String subtitle;
  final Map<String, String> params;
}

const _picks = <_StarterPick>[
  _StarterPick(Network.reddit, 'r/worldnews', 'What\'s happening globally',
      {'subreddit': 'worldnews'}),
  _StarterPick(Network.reddit, 'r/technology', 'Tech news and discussion',
      {'subreddit': 'technology'}),
  _StarterPick(Network.reddit, 'r/space', 'Space exploration and astronomy',
      {'subreddit': 'space'}),
  _StarterPick(Network.mastodon, 'mastodon.social · local',
      'Posts from the largest Mastodon instance',
      {'instance': 'mastodon.social', 'local': 'true'}),
  _StarterPick(Network.mastodon, 'fosstodon.org · local',
      'Open-source and tech community',
      {'instance': 'fosstodon.org', 'local': 'true'}),
  _StarterPick(Network.bluesky, '@bsky.app', 'Official Bluesky updates',
      {'handle': 'bsky.app'}),
  _StarterPick(Network.rss, 'The Verge', 'Tech, science and culture',
      {'url': 'https://www.theverge.com/rss/index.xml'}),
  _StarterPick(Network.rss, 'Ars Technica', 'In-depth tech journalism',
      {'url': 'https://feeds.arstechnica.com/arstechnica/index'}),
  _StarterPick(Network.rss, 'BBC World News', 'Global news headlines',
      {'url': 'https://feeds.bbci.co.uk/news/world/rss.xml'}),
  _StarterPick(Network.rss, 'Hacker News', 'Front page of Hacker News',
      {'url': 'https://news.ycombinator.com/rss'}),
];

/// One-tap curated sources so a fresh install has a live feed in seconds.
class StarterPicksScreen extends StatefulWidget {
  const StarterPicksScreen({super.key});

  @override
  State<StarterPicksScreen> createState() => _StarterPicksScreenState();
}

class _StarterPicksScreenState extends State<StarterPicksScreen> {
  final _selected = <_StarterPick>{};
  bool _saving = false;

  Future<void> _addSelected() async {
    setState(() => _saving = true);
    final state = context.read<AppState>();
    final navigator = Navigator.of(context);

    final base = DateTime.now().microsecondsSinceEpoch;
    final sources = [
      for (final (i, pick) in _selected.indexed)
        FeedSource(
          id: '${base + i}',
          network: pick.network,
          displayName: pick.title,
          params: pick.params,
        ),
    ];
    await state.addSources(sources);
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Quick start')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Pick a few sources to fill your feed right away. '
              'None of these need an account, and you can remove them anytime.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final pick in _picks)
                  CheckboxListTile(
                    secondary: CircleAvatar(
                      backgroundColor:
                          pick.network.color.withValues(alpha: 0.15),
                      child:
                          Icon(pick.network.icon, color: pick.network.color),
                    ),
                    title: Text(pick.title),
                    subtitle: Text(pick.subtitle),
                    value: _selected.contains(pick),
                    onChanged: (v) => setState(() =>
                        v == true ? _selected.add(pick) : _selected.remove(pick)),
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected.isEmpty || _saving ? null : _addSelected,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_selected.isEmpty
                          ? 'Select some sources'
                          : 'Add ${_selected.length} source${_selected.length == 1 ? '' : 's'}'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
