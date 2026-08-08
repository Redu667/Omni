import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/network.dart';
import '../state/app_state.dart';
import 'add_source_screen.dart';
import 'post_card.dart';
import 'saved_screen.dart';
import 'settings_screen.dart';
import 'starter_picks_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Omni'),
        actions: [
          if (state.saved.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.bookmark_border),
              tooltip: 'Saved posts',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SavedScreen()),
              ),
            ),
          if (state.unreadCount > 0)
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'Mark all as read',
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final count = state.unreadCount;
                await state.markAllRead();
                messenger.showSnackBar(
                    SnackBar(content: Text('Marked $count as read')));
              },
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
        bottom: state.activeNetworks.length > 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: _FilterBar(state: state),
              )
            : null,
      ),
      body: !state.initialized
          ? const Center(child: CircularProgressIndicator())
          : state.sources.isEmpty
              ? const _EmptyState()
              : _Feed(state: state),
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

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final networks = state.activeNetworks.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('All'),
              selected: state.filter == null,
              onSelected: (_) => state.setFilter(null),
            ),
          ),
          for (final network in networks)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                avatar: Icon(network.icon,
                    size: 16,
                    color: state.filter == network ? null : network.color),
                label: Text(network.label),
                selected: state.filter == network,
                onSelected: (_) =>
                    state.setFilter(state.filter == network ? null : network),
              ),
            ),
        ],
      ),
    );
  }
}

class _Feed extends StatefulWidget {
  const _Feed({required this.state});

  final AppState state;

  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  /// Fetches the next page a screen ahead of the bottom, so scrolling
  /// rarely stops to wait.
  void _onScroll() {
    if (!_controller.hasClients) return;
    final remaining =
        _controller.position.maxScrollExtent - _controller.position.pixels;
    if (remaining < MediaQuery.of(context).size.height) {
      widget.state.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final items = state.items;

    return RefreshIndicator(
      onRefresh: state.refresh,
      child: Column(
        children: [
          if (state.loading) const LinearProgressIndicator(minHeight: 2),
          if (state.errors.isNotEmpty)
            MaterialBanner(
              content: Text(
                state.errors.join('\n'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              leading: const Icon(Icons.warning_amber),
              actions: [
                TextButton(
                  onPressed: state.refresh,
                  child: const Text('Retry'),
                ),
              ],
            ),
          if (state.showingCached)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.history,
                      size: 15, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Showing your last saved timeline — pull to refresh.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          if (state.hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.filter_alt,
                      size: 14, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    '${state.hiddenCount} hidden by filters',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.outline),
                  ),
                ],
              ),
            ),
          Expanded(
            child: items.isEmpty && !state.loading
                ? ListView(
                    children: const [
                      SizedBox(height: 160),
                      Center(child: Text('Nothing here yet — pull to refresh.')),
                    ],
                  )
                : ListView.builder(
                    controller: _controller,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: items.length + 1,
                    itemBuilder: (_, i) => i < items.length
                        ? PostCard(item: items[i])
                        : _FeedFooter(state: state),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.dynamic_feed,
                size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Welcome to Omni', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'One timeline for Mastodon, Bluesky, Reddit, Twitter and RSS.\n'
              'Add your first source to get started.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Quick start'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StarterPicksScreen()),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add a source manually'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddSourceScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Sits below the last post: a spinner while more is coming, or a quiet
/// note once every source has run out.
class _FeedFooter extends StatelessWidget {
  const _FeedFooter({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (state.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: TextButton(
            onPressed: state.loadMore,
            child: const Text('Load more'),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      child: Center(
        child: Text(
          "That's everything your sources have.",
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ),
    );
  }
}
