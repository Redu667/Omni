import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/feed_item.dart';
import '../models/network.dart';
import '../state/app_state.dart';
import 'post_card.dart';

/// Recent posts by one account, reached by tapping an author anywhere.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.item});

  /// The post the author was tapped from — carries the handle and, crucially,
  /// which source knows how to look them up.
  final FeedItem item;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<FeedItem>? _posts;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final posts = await context.read<AppState>().fetchAuthorPosts(widget.item);
      if (mounted) {
        setState(() {
          _posts = posts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _mute() async {
    final item = widget.item;
    final label = item.handle ?? item.author;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await context.read<AppState>().muteAccount(label);
    messenger.showSnackBar(SnackBar(content: Text('Muted $label')));
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final posts = _posts ?? const <FeedItem>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(item.author, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: (choice) => switch (choice) {
              'mute' => _mute(),
              'open' => launchUrl(Uri.parse(_profileUrl(item)!),
                  mode: LaunchMode.externalApplication),
              _ => null,
            },
            itemBuilder: (_) => [
              if (_profileUrl(item) != null)
                const PopupMenuItem(
                    value: 'open', child: Text('Open profile in browser')),
              const PopupMenuItem(value: 'mute', child: Text('Mute account')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Header(item: item, theme: theme)),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        _error!.replaceFirst(RegExp(r'^.*?: '), ''),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                          onPressed: _load, child: const Text('Try again')),
                    ],
                  ),
                ),
              )
            else if (posts.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text('No posts to show.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: posts.length,
                itemBuilder: (_, i) => PostCard(item: posts[i]),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  /// Best-effort web profile link, per network's URL scheme.
  static String? _profileUrl(FeedItem item) {
    final handle = item.handle?.replaceFirst(RegExp(r'^@'), '');
    return switch (item.network) {
      Network.bluesky when handle != null =>
        'https://bsky.app/profile/$handle',
      Network.twitter when handle != null => 'https://x.com/$handle',
      Network.reddit =>
        'https://www.reddit.com/user/${item.author.replaceFirst(RegExp(r'^/?u/'), '')}',
      // A fediverse handle is user@instance, which maps to that instance.
      Network.mastodon when handle != null && handle.contains('@') =>
        'https://${handle.split('@').last}/@${handle.split('@').first}',
      _ => null,
    };
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item, required this.theme});

  final FeedItem item;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: item.network.color.withValues(alpha: 0.15),
            foregroundImage: item.avatarUrl != null
                ? CachedNetworkImageProvider(item.avatarUrl!)
                : null,
            child: Icon(item.network.icon,
                size: 28, color: item.network.color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.author, style: theme.textTheme.titleLarge),
                if (item.handle != null)
                  Text(item.handle!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline)),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(item.network.icon,
                          size: 13, color: item.network.color),
                      const SizedBox(width: 5),
                      Text(item.network.label,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
