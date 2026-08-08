import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../models/feed_item.dart';
import '../models/network.dart';
import '../state/app_state.dart';
import 'image_viewer_screen.dart';
import 'post_actions.dart';
import 'post_extras.dart';
import 'post_view_screen.dart';
import 'profile_screen.dart';

/// Renders a post with Flutter widgets — same visual language as the
/// timeline — rather than embedding a browser. Replies load underneath
/// when the network has them.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.item});

  final FeedItem item;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  PostThread? _thread;
  bool _loading = true;
  String? _threadError;

  /// Held separately from [_thread] because loading more replies splices
  /// them into place rather than replacing the whole conversation.
  List<ThreadEntry> _replies = const [];
  MoreReplies? _rootMore;

  String? _sort;
  final _expanding = <MoreReplies>{};

  @override
  void initState() {
    super.initState();
    _loadThread();
  }

  Future<void> _loadThread() async {
    setState(() {
      _loading = true;
      _threadError = null;
    });
    try {
      final thread =
          await context.read<AppState>().fetchThread(widget.item, sort: _sort);
      if (mounted) {
        setState(() {
          _thread = thread;
          _replies = [...thread.replies];
          _rootMore = thread.more;
          _expanding.clear();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _threadError = e.toString();
        });
      }
    }
  }

  /// Reddit takes at most 100 ids at a time, so a very long thread needs the
  /// button more than once. What's left over becomes the next batch.
  static MoreReplies? _remainderOf(MoreReplies more, int loaded) {
    final rest = more.ids.skip(100).toList();
    if (rest.isEmpty) return null;
    return MoreReplies(
      count: (more.count - loaded).clamp(rest.length, more.count),
      ids: rest,
      depth: more.depth,
    );
  }

  /// [under] is the reply whose replies were truncated, or null for the
  /// top-level "more comments".
  Future<void> _loadMore(MoreReplies more, {ThreadEntry? under}) async {
    setState(() => _expanding.add(more));
    try {
      final loaded = await context
          .read<AppState>()
          .fetchMoreReplies(widget.item, more, sort: _sort);
      if (!mounted) return;

      setState(() {
        _expanding.remove(more);
        final remainder = _remainderOf(more, loaded.length);
        final replies = [..._replies];

        if (under == null) {
          replies.addAll(loaded);
          _rootMore = remainder;
        } else {
          final at = replies.indexOf(under);
          if (at < 0) return;
          replies[at] = under.withMore(remainder);
          // Slot them in after everything already nested under this
          // comment, which is where the missing replies belong.
          var end = at + 1;
          while (end < replies.length && replies[end].depth > under.depth) {
            end++;
          }
          replies.insertAll(end, loaded);
        }
        _replies = replies;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _expanding.remove(more));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't load the rest of the thread")),
      );
    }
  }

  Future<void> _pickSort(Map<String, String> sorts) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in sorts.entries)
              RadioListTile<String>(
                value: entry.key,
                groupValue: _sort ?? sorts.keys.first,
                title: Text(entry.value),
                onChanged: (v) => Navigator.of(sheetContext).pop(v),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen == _sort) return;
    setState(() => _sort = chosen);
    await _loadThread();
  }

  Future<void> _openOriginal({required bool external}) async {
    final url = widget.item.url;
    if (url == null) return;
    if (external) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PostViewScreen(item: widget.item)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final thread = _thread ?? PostThread.empty;
    final ancestors = thread.ancestors;
    final replies = _replies;
    final sorts = context.read<AppState>().commentSorts(item);
    final rootMore = _rootMore;

    return Scaffold(
      appBar: AppBar(
        title: Text(item.network.label),
        actions: [
          IconButton(
            icon: Icon(
              context.watch<AppState>().isSaved(item)
                  ? Icons.bookmark
                  : Icons.bookmark_border,
            ),
            tooltip: 'Save',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final nowSaved = await context.read<AppState>().toggleSaved(item);
              messenger.showSnackBar(
                SnackBar(
                  content: Text(nowSaved ? 'Saved' : 'Removed from saved'),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More',
            onPressed: () => showPostActions(context, item),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadThread,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 32),
          itemCount:
              ancestors.length + replies.length + 2 + (rootMore == null ? 0 : 1),
          itemBuilder: (context, index) {
            // What this post was replying to, oldest first.
            if (index < ancestors.length) {
              return _AncestorTile(item: ancestors[index], theme: theme);
            }
            final offset = index - ancestors.length;
            if (offset == 0) {
              return _PostBody(
                item: item,
                isReply: ancestors.isNotEmpty,
                onOpenOriginal: () => _openOriginal(
                  external: !context.read<AppState>().openInApp,
                ),
              );
            }
            if (offset == 1) {
              return _ThreadHeader(
                loading: _loading,
                error: _threadError,
                count: replies.length,
                network: item.network,
                onRetry: _loadThread,
                sorts: sorts,
                sort: _sort,
                onPickSort: sorts.isEmpty ? null : () => _pickSort(sorts),
              );
            }
            if (offset - 2 >= replies.length) {
              return _LoadMoreButton(
                more: rootMore!,
                loading: _expanding.contains(rootMore),
                onPressed: () => _loadMore(rootMore),
              );
            }
            final entry = replies[offset - 2];
            return _ReplyTile(
              entry: entry,
              theme: theme,
              expanding: entry.more != null && _expanding.contains(entry.more),
              onLoadMore: entry.more == null
                  ? null
                  : () => _loadMore(entry.more!, under: entry),
            );
          },
        ),
      ),
    );
  }
}

class _PostBody extends StatefulWidget {
  const _PostBody({
    required this.item,
    required this.onOpenOriginal,
    this.isReply = false,
  });

  final FeedItem item;
  final VoidCallback onOpenOriginal;

  /// True when something is displayed above, so the post reads as an answer.
  final bool isReply;

  @override
  State<_PostBody> createState() => _PostBodyState();
}

class _PostBodyState extends State<_PostBody> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final hidden = item.needsReveal && !_revealed;

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: widget.isReply
          ? BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.repostedBy != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.repeat,
                    size: 15,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${item.repostedBy} boosted',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          InkWell(
            onTap: context.read<AppState>().supportsAuthorFeed(item)
                ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(item: item),
                    ),
                  )
                : null,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: item.network.color.withValues(alpha: 0.15),
                  foregroundImage: item.avatarUrl != null
                      ? CachedNetworkImageProvider(item.avatarUrl!)
                      : null,
                  child: Icon(
                    item.network.icon,
                    size: 22,
                    color: item.network.color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.author, style: theme.textTheme.titleMedium),
                      Text(
                        [
                          if (item.handle != null) item.handle!,
                          if (item.context != null) item.context!,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                if (context.read<AppState>().supportsAuthorFeed(item))
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: theme.colorScheme.outline,
                  ),
              ],
            ),
          ),
          if (item.flair != null)
            Align(
              alignment: Alignment.centerLeft,
              child: FlairChip(flair: item.flair!),
            ),
          if (item.title?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SelectableText(
                item.title!,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (hidden)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.visibility_off_outlined,
                          size: 18,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.contentWarning ?? 'Marked sensitive',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonal(
                      onPressed: () => setState(() => _revealed = true),
                      child: const Text('Show anyway'),
                    ),
                  ],
                ),
              ),
            ),
          if (item.body.isNotEmpty && !hidden)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText(
                item.body,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
              ),
            ),
          if (item.imageUrls.isNotEmpty && !hidden)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                children: [
                  for (final (index, image) in item.media.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            // Opens the picture full-screen, where it can be
                            // zoomed — inline it's capped to the column width.
                            onTap: () =>
                                Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ImageViewerScreen(
                                media: item.media,
                                initialIndex: index,
                              ),
                            )),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Semantics(
                                label: image.alt,
                                image: true,
                                child: CachedNetworkImage(
                                  imageUrl: image.url,
                                  fit: BoxFit.contain,
                                  width: double.infinity,
                                  placeholder: (_, _) => Container(
                                    height: 180,
                                    color: theme
                                        .colorScheme.surfaceContainerHighest,
                                  ),
                                  errorWidget: (_, _, _) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ),
                          // Alt text is the author describing their own
                          // image; showing it is useful to everyone, not
                          // only to screen readers.
                          if (image.hasAlt)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                image.alt!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (!hidden) ...[
            if (item.quoted != null)
              QuotedPost(item: item.quoted!, compact: false),
            if (item.poll != null) PollView(poll: item.poll!),
            if (item.linkCard != null) LinkCardView(card: item.linkCard!),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              timeago.format(item.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          if (item.likes != null ||
              item.reposts != null ||
              item.replies != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
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
                    _Stat(icon: Icons.arrow_upward, value: item.likes!),
                ],
              ),
            ),
          if (item.url != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.article_outlined, size: 18),
                label: Text(
                  item.network == Network.rss
                      ? 'Read full article'
                      : 'View original',
                ),
                onPressed: widget.onOpenOriginal,
              ),
            ),
        ],
      ),
    );
  }
}

class _ThreadHeader extends StatelessWidget {
  const _ThreadHeader({
    required this.loading,
    required this.error,
    required this.count,
    required this.network,
    required this.onRetry,
    this.sorts = const {},
    this.sort,
    this.onPickSort,
  });

  final bool loading;
  final String? error;
  final int count;
  final Network network;
  final VoidCallback onRetry;

  /// Empty where the network has no comment ordering to choose from.
  final Map<String, String> sorts;
  final String? sort;
  final VoidCallback? onPickSort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Row(
          children: [
            Expanded(
              child: Text(
                "Couldn't load replies",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (count == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Text(
          network == Network.rss
              ? 'Feeds have no discussion to show.'
              : 'No replies yet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count ${count == 1 ? 'reply' : 'replies'}',
              style: theme.textTheme.titleSmall,
            ),
          ),
          if (onPickSort != null)
            TextButton.icon(
              onPressed: onPickSort,
              icon: const Icon(Icons.sort, size: 18),
              label: Text(sorts[sort ?? sorts.keys.first] ?? 'Sort'),
            ),
        ],
      ),
    );
  }
}

/// "Load the N replies the network held back."
class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({
    required this.more,
    required this.loading,
    required this.onPressed,
  });

  final MoreReplies more;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: loading ? null : onPressed,
          icon: loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.expand_more, size: 18),
          label: Text(
            loading
                ? 'Loading…'
                : '${more.count} more '
                    '${more.count == 1 ? 'reply' : 'replies'}',
          ),
        ),
      ),
    );
  }
}

class _ReplyTile extends StatelessWidget {
  const _ReplyTile({
    required this.entry,
    required this.theme,
    this.expanding = false,
    this.onLoadMore,
  });

  final ThreadEntry entry;
  final ThemeData theme;

  /// Null unless this comment has replies the network held back.
  final VoidCallback? onLoadMore;
  final bool expanding;

  /// Indentation stops growing past a few levels so deep chains stay readable
  /// on a phone.
  static const _maxIndentLevel = 5;

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final indent = (entry.depth.clamp(0, _maxIndentLevel)) * 12.0;

    return Container(
      margin: EdgeInsets.fromLTRB(16 + indent, 0, 16, 0),
      padding: const EdgeInsets.only(left: 10, top: 10, bottom: 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: entry.depth == 0
                ? Colors.transparent
                : theme.colorScheme.outlineVariant,
            width: entry.depth == 0 ? 0 : 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.handle ?? item.author,
                  style: theme.textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                timeago.format(item.createdAt, locale: 'en_short'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(item.text, style: theme.textTheme.bodyMedium),
          if (item.likes != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_upward,
                    size: 13,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${item.likes}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          if (entry.more != null && onLoadMore != null)
            _LoadMoreButton(
              more: entry.more!,
              loading: expanding,
              onPressed: onLoadMore!,
            ),
        ],
      ),
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
      padding: const EdgeInsets.only(right: 24),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.outline),
          const SizedBox(width: 5),
          Text(
            '$value',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}


/// A post further up the conversation, shown above the one being viewed so
/// a reply isn't an answer with no question.
class _AncestorTile extends StatelessWidget {
  const _AncestorTile({required this.item, required this.theme});

  final FeedItem item;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => PostDetailScreen(item: item)),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.outlineVariant, width: 2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(item.handle ?? item.author,
                      style: theme.textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis),
                ),
                Text('in reply to',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.needsReveal
                  ? (item.contentWarning ?? 'Marked sensitive')
                  : item.text,
              style: theme.textTheme.bodyMedium,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
