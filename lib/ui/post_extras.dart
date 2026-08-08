import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/feed_item.dart';
import '../models/network.dart';

/// The quoted post, rendered inline. Shared by the timeline and the detail
/// view so a quote reads the same in both.
class QuotedPost extends StatelessWidget {
  const QuotedPost({super.key, required this.item, this.compact = true});

  final FeedItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (item.avatarUrl != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: CircleAvatar(
                    radius: 9,
                    foregroundImage:
                        CachedNetworkImageProvider(item.avatarUrl!),
                    backgroundColor:
                        item.network.color.withValues(alpha: 0.15),
                  ),
                ),
              Flexible(
                child: Text(
                  item.author,
                  style: theme.textTheme.labelMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.handle != null) ...[
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    item.handle!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          if (item.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                item.text,
                style: theme.textTheme.bodySmall,
                maxLines: compact ? 4 : 20,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

/// A preview of where a link post points.
class LinkCardView extends StatelessWidget {
  const LinkCardView({super.key, required this.card});

  final LinkCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final host = Uri.tryParse(card.url)?.host ?? card.url;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        onTap: () => launchUrl(Uri.parse(card.url),
            mode: LaunchMode.externalApplication),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (card.imageUrl != null)
                CachedNetworkImage(
                  imageUrl: card.imageUrl!,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    if (card.title != null && card.title != host) ...[
                      const SizedBox(height: 2),
                      Text(
                        card.title!,
                        style: theme.textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (card.description != null &&
                        card.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        card.description!,
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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

/// Poll options with their share of the vote. Omni doesn't vote — it reads —
/// so this shows results rather than offering a choice.
class PollView extends StatelessWidget {
  const PollView({super.key, required this.poll});

  final Poll poll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final option in poll.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(option.title,
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(poll.shareOf(option) * 100).round()}%',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: poll.shareOf(option),
                      minHeight: 5,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
          Text(
            [
              '${poll.totalVotes} ${poll.totalVotes == 1 ? 'vote' : 'votes'}',
              if (poll.expired) 'closed',
            ].join(' · '),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

/// Reddit post flair, which is how many subreddits organise themselves.
class FlairChip extends StatelessWidget {
  const FlairChip({super.key, required this.flair});

  final String flair;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        flair,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
      ),
    );
  }
}
