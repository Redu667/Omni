import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/network.dart';
import '../state/app_state.dart';
import 'add_source_screen.dart';
import 'post_card.dart';
import 'sources_screen.dart';
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
          IconButton(
            icon: const Icon(Icons.rss_feed),
            tooltip: 'Manage sources',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SourcesScreen()),
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

class _Feed extends StatelessWidget {
  const _Feed({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
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
          Expanded(
            child: items.isEmpty && !state.loading
                ? ListView(
                    children: const [
                      SizedBox(height: 160),
                      Center(child: Text('Nothing here yet — pull to refresh.')),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: items.length,
                    itemBuilder: (_, i) => PostCard(item: items[i]),
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
