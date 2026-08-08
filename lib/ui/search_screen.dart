import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/post_search.dart';
import '../state/app_state.dart';
import 'post_card.dart';

/// Searches the timeline already on the device. The matching itself lives in
/// [searchPosts] so it can be tested without building a widget.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    // Searches everything loaded, not just the current collection or
    // network view — you're looking for something, not browsing.
    final results = searchPosts(state.allItems, _query);
    final searching = searchTerms(_query).isNotEmpty;

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
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: !searching
          ? _Hint(
              theme: theme,
              text: 'Searches the ${state.allItems.length} posts already '
                  'loaded — titles, bodies, authors, flair and quoted posts.',
            )
          : results.isEmpty
              ? _Hint(
                  theme: theme,
                  text: 'Nothing matching "$_query" in the posts you have '
                      'loaded. Scrolling further back may turn up more.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: results.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text(
                          '${results.length} '
                          '${results.length == 1 ? 'result' : 'results'}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      );
                    }
                    return PostCard(item: results[i - 1]);
                  },
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
