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

  final DateTime createdAt;
}
