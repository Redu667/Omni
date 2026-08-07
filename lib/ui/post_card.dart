import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../models/feed_item.dart';
import '../models/network.dart';
import '../state/app_state.dart';
import 'post_view_screen.dart';

class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.item});

  final FeedItem item;

  Future<void> _openExternally() async {
    final url = item.url;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _open(BuildContext context) {
    if (item.url == null) return;
    if (context.read<AppState>().openInApp) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PostViewScreen(item: item)),
      );
    } else {
      _openExternally();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        onLongPress: _openExternally,
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
                      Icon(Icons.repeat,
                          size: 14, color: theme.colorScheme.outline),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${item.repostedBy} boosted',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              _Header(item: item),
              if (item.title != null && item.title!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(item.title!,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              if (item.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    item.text,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 12,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (item.imageUrls.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
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
              if (item.likes != null ||
                  item.reposts != null ||
                  item.replies != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      if (item.replies != null)
                        _Stat(icon: Icons.chat_bubble_outline, value: item.replies!),
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
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item});

  final FeedItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final networkColor = item.network.color;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: networkColor.withValues(alpha: 0.15),
          foregroundImage: item.avatarUrl != null
              ? CachedNetworkImageProvider(item.avatarUrl!)
              : null,
          child: Icon(item.network.icon, size: 20, color: networkColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.author,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis),
              Text(
                [
                  if (item.handle != null) item.handle!,
                  if (item.context != null) item.context!,
                ].join(' · '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
                overflow: TextOverflow.ellipsis,
              ),
            ],
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
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
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
          Text(_compact(value),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
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
