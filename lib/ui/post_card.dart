import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:provider/provider.dart';

import '../models/feed_item.dart';
import '../models/network.dart';
import '../state/app_state.dart';
import 'post_actions.dart';
import 'post_detail_screen.dart';
import 'profile_screen.dart';

class PostCard extends StatefulWidget {
  const PostCard({super.key, required this.item});

  final FeedItem item;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _revealed = false;

  FeedItem get item => widget.item;

  /// Opens Omni's own rendering of the post. Everything else — saving, the
  /// author's other posts, the browser — lives behind a long-press.
  void _open(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PostDetailScreen(item: item)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final read = context.watch<AppState>().isRead(item);

    return Opacity(
      // Read posts stay in place but recede, so the eye skips them.
      opacity: read ? 0.55 : 1,
      child: Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        onLongPress: () => showPostActions(context, item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.repostedBy != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.repeat,
                        size: 14,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${item.repostedBy} boosted',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              _Header(
                item: item,
                onTapAuthor: context.read<AppState>().supportsAuthorFeed(item)
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(item: item),
                        ),
                      )
                    : null,
              ),
              if (item.title != null && item.title!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    item.title!,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (item.needsReveal && !_revealed)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _RevealPrompt(
                    item: item,
                    onReveal: () => setState(() => _revealed = true),
                  ),
                ),
              if (item.text.isNotEmpty && (!item.needsReveal || _revealed))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    item.text,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 12,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (item.imageUrls.isNotEmpty && (!item.needsReveal || _revealed))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Semantics(
                          label: item.media.first.alt,
                          image: true,
                          child: CachedNetworkImage(
                            imageUrl: item.imageUrls.first,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 200,
                            placeholder: (_, _) => Container(
                              height: 200,
                              color: theme.colorScheme.surfaceContainerHighest,
                            ),
                            errorWidget: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      if (item.imageUrls.length > 1)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: _Chip(
                              label: '+${item.imageUrls.length - 1}',
                              theme: theme),
                        ),
                      if (item.media.first.hasAlt)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: _Chip(label: 'ALT', theme: theme),
                        ),
                    ],
                  ),
                ),
              if (item.likes != null ||
                  item.reposts != null ||
                  item.replies != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      if (item.replies != null)
                        _Stat(
                          icon: Icons.chat_bubble_outline,
                          value: item.replies!,
                        ),
                      if (item.reposts != null)
                        _Stat(icon: Icons.repeat, value: item.reposts!),
                      if (item.likes != null)
                        _Stat(icon: Icons.favorite_border, value: item.likes!),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item, this.onTapAuthor});

  final FeedItem item;

  /// Null where the network has no author feed to open.
  final VoidCallback? onTapAuthor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final networkColor = item.network.color;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onTapAuthor,
          child: CircleAvatar(
            radius: 20,
            backgroundColor: networkColor.withValues(alpha: 0.15),
            foregroundImage: item.avatarUrl != null
                ? CachedNetworkImageProvider(item.avatarUrl!)
                : null,
            child: Icon(item.network.icon, size: 20, color: networkColor),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: onTapAuthor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.author,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  [
                    if (item.handle != null) item.handle!,
                    if (item.context != null) item.context!,
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Icon(item.network.icon, size: 16, color: networkColor),
            const SizedBox(height: 2),
            Text(
              timeago.format(item.createdAt, locale: 'en_short'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value});

  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Row(
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Text(
            _compact(value),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// Stands in for a post the author flagged, so a content warning is honoured
/// rather than decorative.
class _RevealPrompt extends StatelessWidget {
  const _RevealPrompt({required this.item, required this.onReveal});

  final FeedItem item;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = item.contentWarning;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.visibility_off_outlined,
                size: 16,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  warning ?? 'Marked sensitive',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onReveal,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Show anyway'),
            ),
          ),
        ],
      ),
    );
  }
}


/// Small overlay badge for image counts and the ALT marker.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.theme});

  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }
}
