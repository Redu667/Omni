import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../models/feed_item.dart';
import '../models/network.dart';
import '../state/app_state.dart';
import 'post_view_screen.dart';

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
  List<ThreadEntry>? _thread;
  bool _loading = true;
  String? _threadError;

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
      final thread = await context.read<AppState>().fetchThread(widget.item);
      if (mounted) {
        setState(() {
          _thread = thread;
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
    final thread = _thread ?? const <ThreadEntry>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(item.network.label),
        actions: [
          if (item.url != null)
            PopupMenuButton<String>(
              onSelected: (choice) => switch (choice) {
                'in_app' => _openOriginal(external: false),
                'browser' => _openOriginal(external: true),
                'copy' => Clipboard.setData(ClipboardData(text: item.url!))
                    .then((_) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied')));
                  }),
                _ => null,
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'in_app', child: Text('Open original in Omni')),
                PopupMenuItem(
                    value: 'browser', child: Text('Open in browser')),
                PopupMenuItem(value: 'copy', child: Text('Copy link')),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadThread,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 32),
          itemCount: thread.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _PostBody(
                item: item,
                onOpenOriginal: () => _openOriginal(
                    external: !context.read<AppState>().openInApp),
              );
            }
            if (index == 1) {
              return _ThreadHeader(
                loading: _loading,
                error: _threadError,
                count: thread.length,
                network: item.network,
                onRetry: _loadThread,
              );
            }
            final entry = thread[index - 2];
            return _ReplyTile(entry: entry, theme: theme);
          },
        ),
      ),
    );
  }
}

class _PostBody extends StatelessWidget {
  const _PostBody({required this.item, required this.onOpenOriginal});

  final FeedItem item;
  final VoidCallback onOpenOriginal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.repostedBy != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.repeat, size: 15, color: theme.colorScheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('${item.repostedBy} boosted',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: item.network.color.withValues(alpha: 0.15),
                foregroundImage: item.avatarUrl != null
                    ? CachedNetworkImageProvider(item.avatarUrl!)
                    : null,
                child: Icon(item.network.icon,
                    size: 22, color: item.network.color),
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
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.title?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SelectableText(item.title!,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
          if (item.body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText(
                item.body,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
              ),
            ),
          if (item.imageUrls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                children: [
                  for (final url in item.imageUrls)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          placeholder: (_, _) => Container(
                            height: 180,
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          errorWidget: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              timeago.format(item.createdAt),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          if (item.likes != null || item.reposts != null || item.replies != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  if (item.replies != null)
                    _Stat(icon: Icons.chat_bubble_outline, value: item.replies!),
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
                label: Text(item.network == Network.rss
                    ? 'Read full article'
                    : 'View original'),
                onPressed: onOpenOriginal,
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
  });

  final bool loading;
  final String? error;
  final int count;
  final Network network;
  final VoidCallback onRetry;

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
              child: Text("Couldn't load replies",
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline)),
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
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text('$count ${count == 1 ? 'reply' : 'replies'}',
          style: theme.textTheme.titleSmall),
    );
  }
}

class _ReplyTile extends StatelessWidget {
  const _ReplyTile({required this.entry, required this.theme});

  final ThreadEntry entry;
  final ThemeData theme;

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
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
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
                  Icon(Icons.arrow_upward,
                      size: 13, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Text('${item.likes}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
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
          Text('$value',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }
}
