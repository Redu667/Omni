import 'network.dart';

/// A single post/entry normalized from any network into one shape.
class FeedItem {
  FeedItem({
    required this.id,
    required this.sourceId,
    required this.network,
    required this.author,
    required this.createdAt,
    this.handle,
    this.avatarUrl,
    this.title,
    this.text = '',
    this.url,
    this.imageUrls = const [],
    this.repostedBy,
    this.likes,
    this.reposts,
    this.replies,
    this.context,
    this.fullText,
    this.nativeId,
    this.contentWarning,
    this.sensitive = false,
  });

  /// Globally unique: `sourceId:nativeId`.
  final String id;
  final String sourceId;
  final Network network;

  final String author;

  /// e.g. "@user@instance", "@user.bsky.social", "u/user".
  final String? handle;
  final String? avatarUrl;

  /// Headline for link-style entries (Reddit, RSS).
  final String? title;
  final String text;

  /// Permalink to open in a browser.
  final String? url;
  final List<String> imageUrls;

  /// Who boosted/reposted this into the timeline, if anyone.
  final String? repostedBy;

  final int? likes;
  final int? reposts;
  final int? replies;

  /// Extra origin info, e.g. "r/flutter" or the feed's title.
  final String? context;

  /// Untruncated body, when [text] had to be shortened for the timeline.
  /// The detail view shows this in preference to [text].
  final String? fullText;

  /// The network's own identifier for this post — a Mastodon status id, an
  /// `at://` URI, a Reddit permalink. Needed to fetch the reply thread,
  /// since [id] is namespaced to the source.
  final String? nativeId;

  /// The author's own warning about what's underneath — Mastodon's
  /// spoiler text. Non-null means the body starts hidden.
  final String? contentWarning;

  /// Marked sensitive by the author or the platform (Mastodon's `sensitive`,
  /// Reddit's `over_18`). Media starts blurred.
  final bool sensitive;

  bool get needsReveal => (contentWarning?.isNotEmpty ?? false) || sensitive;

  final DateTime createdAt;

  /// What the detail view should render as the post body.
  String get body => (fullText?.isNotEmpty ?? false) ? fullText! : text;
}

/// One post in a reply thread, flattened with its nesting level so the UI
/// can indent without recursing through a tree.
class ThreadEntry {
  const ThreadEntry({required this.item, this.depth = 0});

  final FeedItem item;
  final int depth;
}
