import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/feed_item.dart';
import '../services/post_search.dart';
import '../state/app_state.dart';
import 'post_card.dart';

/// Searches the timeline already on the device, and — on request — the
/// networks themselves. The local matching lives in [searchPosts] so it can
/// be tested without building a widget.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  /// Results from the networks, and the query they answer. Held separately
  /// from the local ones so typing another letter doesn't silently leave
  /// stale results on screen.
  List<FeedItem>? _remote;
  String? _remoteQuery;
  bool _searchingNetworks = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _searchNetworks() async {
    final query = _query.trim();
    if (query.isEmpty) return;

    setState(() => _searchingNetworks = true);
    try {
      final found = await context.read<AppState>().searchNetworks(query);
      if (!mounted) return;
      setState(() {
        _remote = found;
        _remoteQuery = query;
        _searchingNetworks = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searchingNetworks = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't reach your services")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    // Searches everything loaded, not just the current collection or
    // network view — you're looking for something, not browsing.
    final local = searchPosts(state.allItems, _query);
    final searching = searchTerms(_query).isNotEmpty;

    // Only the results that answer what's currently typed. Anything already
    // on screen locally isn't repeated.
    final localIds = {for (final i in local) i.id};
    final remote = _remoteQuery == _query.trim()
        ? (_remote ?? const <FeedItem>[])
            .where((i) => !localIds.contains(i.id))
            .toList()
        : const <FeedItem>[];

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search your feed',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
          onSubmitted: (_) {
            if (state.canSearchNetworks) _searchNetworks();
          },
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                setState(() {
                  _query = '';
                  _remote = null;
                  _remoteQuery = null;
                });
              },
            ),
        ],
      ),
      body: !searching
          ? _Hint(
              theme: theme,
              text: 'Searches the ${state.allItems.length} posts already '
                  'loaded — titles, bodies, authors, flair and quoted posts. '
                  'Press enter to ask your services for more.',
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              // Local results, then the network header, then network results.
              itemCount: local.length + 2 + remote.length,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return _Count(
                    theme: theme,
                    label: local.isEmpty
                        ? 'Nothing loaded matches "$_query"'
                        : '${local.length} '
                            '${local.length == 1 ? 'result' : 'results'} '
                            'in your feed',
                  );
                }
                if (i <= local.length) return PostCard(item: local[i - 1]);

                if (i == local.length + 1) {
                  return _NetworkSection(
                    theme: theme,
                    enabled: state.canSearchNetworks,
                    loading: _searchingNetworks,
                    // Null until a search has actually run for this query.
                    resultCount:
                        _remoteQuery == _query.trim() ? remote.length : null,
                    onSearch: _searchNetworks,
                  );
                }
                return PostCard(item: remote[i - local.length - 2]);
              },
            ),
    );
  }
}

/// The divider between what was already here and what came from the network.
class _NetworkSection extends StatelessWidget {
  const _NetworkSection({
    required this.theme,
    required this.enabled,
    required this.loading,
    required this.resultCount,
    required this.onSearch,
  });

  final ThemeData theme;
  final bool enabled;
  final bool loading;

  /// Null before a search has run for the current query.
  final int? resultCount;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          'None of your sources can be searched directly — RSS feeds and X '
          'only offer what has already been fetched.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              switch (resultCount) {
                null => 'Not everything is loaded — your services may have '
                    'more.',
                0 => 'Your services turned up nothing else.',
                final n => '$n more from your services',
              },
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          const SizedBox(width: 8),
          if (loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            TextButton.icon(
              onPressed: onSearch,
              icon: const Icon(Icons.travel_explore, size: 18),
              label: Text(resultCount == null ? 'Search services' : 'Again'),
            ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.theme, required this.label});

  final ThemeData theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        label,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.theme, required this.text});

  final ThemeData theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ),
    );
  }
}
