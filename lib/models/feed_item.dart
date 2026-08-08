import 'network.dart';

/// An image attached to a post, with the author's description of it.
///
/// Alt text is carried rather than discarded: Mastodon and Bluesky both have
/// strong alt-text cultures, and dropping it makes posts unreadable to
/// anyone using a screen reader.
class MediaItem {
  const MediaItem({required this.url, this.alt});

  final String url;
  final String? alt;

  bool get hasAlt => alt != null && alt!.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {'url': url, 'alt': alt};

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
        url: json['url'] as String,
        alt: json['alt'] as String?,
      );
}

/// A link a post points at, with whatever preview the network provides.
class LinkCard {
  const LinkCard({required this.url, this.title, this.description, this.imageUrl});

  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
      };

  factory LinkCard.fromJson(Map<String, dynamic> json) => LinkCard(
        url: json['url'] as String,
        title: json['title'] as String?,
        description: json['description'] as String?,
        imageUrl: json['imageUrl'] as String?,
      );
}

/// One choice in a poll.
class PollOption {
  const PollOption({required this.title, this.votes = 0});

  final String title;
  final int votes;

  Map<String, dynamic> toJson() => {'title': title, 'votes': votes};

  factory PollOption.fromJson(Map<String, dynamic> json) => PollOption(
        title: json['title'] as String? ?? '',
        votes: json['votes'] as int? ?? 0,
      );
}

/// A poll attached to a post. Without this, poll posts render as empty
/// text — the question lives in the post body but the options don't.
class Poll {
  const Poll({required this.options, this.totalVotes = 0, this.expiresAt, this.expired = false});

  final List<PollOption> options;
  final int totalVotes;
  final DateTime? expiresAt;
  final bool expired;

  /// Share of the vote for one option, 0..1.
  double shareOf(PollOption option) =>
      totalVotes == 0 ? 0 : option.votes / totalVotes;

  Map<String, dynamic> toJson() => {
        'options': [for (final o in options) o.toJson()],
        'totalVotes': totalVotes,
        'expiresAt': expiresAt?.toIso8601String(),
        'expired': expired,
      };

  factory Poll.fromJson(Map<String, dynamic> json) => Poll(
        options: [
          for (final o in (json['options'] as List? ?? const []))
            PollOption.fromJson((o as Map).cast<String, dynamic>()),
        ],
        totalVotes: json['totalVotes'] as int? ?? 0,
        expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
        expired: json['expired'] as bool? ?? false,
      );
}

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
    this.media = const [],
    this.repostedBy,
    this.likes,
    this.reposts,
    this.replies,
    this.context,
    this.fullText,
    this.nativeId,
    this.contentWarning,
    this.sensitive = false,
    this.quoted,
    this.linkCard,
    this.poll,
    this.flair,
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

  final List<MediaItem> media;

  /// Just the URLs, for the many places that only need those.
  List<String> get imageUrls => [for (final m in media) m.url];

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

  /// A post this one quotes. Showing only the commentary without what it
  /// quotes can invert the meaning entirely, so this is carried one level
  /// deep (a quote of a quote shows the outer one only).
  final FeedItem? quoted;

  /// Preview for a link the post points at.
  final LinkCard? linkCard;

  final Poll? poll;

  /// Reddit's post flair, which is how many subreddits organise themselves.
  final String? flair;

  final DateTime createdAt;

  /// What the detail view should render as the post body.
  String get body => (fullText?.isNotEmpty ?? false) ? fullText! : text;

  /// Saved posts are stored as-is rather than re-fetched, so a post stays
  /// readable even after its source is removed or the network is down.
  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceId': sourceId,
        'network': network.name,
        'author': author,
        'handle': handle,
        'avatarUrl': avatarUrl,
        'title': title,
        'text': text,
        'url': url,
        'media': [for (final m in media) m.toJson()],
        'repostedBy': repostedBy,
        'likes': likes,
        'reposts': reposts,
        'replies': replies,
        'context': context,
        'fullText': fullText,
        'nativeId': nativeId,
        'contentWarning': contentWarning,
        'sensitive': sensitive,
        'quoted': quoted?.toJson(),
        'linkCard': linkCard?.toJson(),
        'poll': poll?.toJson(),
        'flair': flair,
        'createdAt': createdAt.toIso8601String(),
      };

  factory FeedItem.fromJson(Map<String, dynamic> json) => FeedItem(
        id: json['id'] as String,
        sourceId: json['sourceId'] as String? ?? '',
        network: NetworkInfo.fromName(json['network'] as String),
        author: json['author'] as String? ?? '',
        handle: json['handle'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        title: json['title'] as String?,
        text: json['text'] as String? ?? '',
        url: json['url'] as String?,
        media: [
          for (final m in (json['media'] as List? ?? const []))
            MediaItem.fromJson((m as Map).cast<String, dynamic>()),
          // Posts saved before alt text existed stored bare URLs.
          for (final u in (json['imageUrls'] as List? ?? const []))
            MediaItem(url: u as String),
        ],
        repostedBy: json['repostedBy'] as String?,
        likes: json['likes'] as int?,
        reposts: json['reposts'] as int?,
        replies: json['replies'] as int?,
        context: json['context'] as String?,
        fullText: json['fullText'] as String?,
        nativeId: json['nativeId'] as String?,
        contentWarning: json['contentWarning'] as String?,
        sensitive: json['sensitive'] as bool? ?? false,
        quoted: json['quoted'] == null
            ? null
            : FeedItem.fromJson((json['quoted'] as Map).cast<String, dynamic>()),
        linkCard: json['linkCard'] == null
            ? null
            : LinkCard.fromJson(
                (json['linkCard'] as Map).cast<String, dynamic>()),
        poll: json['poll'] == null
            ? null
            : Poll.fromJson((json['poll'] as Map).cast<String, dynamic>()),
        flair: json['flair'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')
                ?.toUtc() ??
            DateTime.now().toUtc(),
      );
}

/// One post in a reply thread, flattened with its nesting level so the UI
/// can indent without recursing through a tree.
class ThreadEntry {
  const ThreadEntry({required this.item, this.depth = 0, this.more});

  final FeedItem item;
  final int depth;

  /// Replies to this comment that the network didn't send, if any.
  final MoreReplies? more;

  ThreadEntry withMore(MoreReplies? more) =>
      ThreadEntry(item: item, depth: depth, more: more);
}

/// A pointer to replies a network held back.
///
/// Reddit truncates long and deep comment trees and hands back a token
/// instead. Dropping it silently is how a 400-comment thread quietly becomes
/// a 40-comment one, so it's carried and offered as "load more".
class MoreReplies {
  const MoreReplies({
    required this.count,
    required this.ids,
    this.depth = 0,
  });

  /// How many comments are hidden, as the network counts them.
  final int count;

  /// Opaque ids to hand back when asking for them.
  final List<String> ids;

  /// Indentation the loaded replies should appear at.
  final int depth;

  /// Reddit also emits "continue this thread" stubs with nothing to request.
  /// Those can't be loaded in place, so they aren't offered.
  bool get isEmpty => ids.isEmpty;
}

/// The conversation around a post: what it was replying to, and what
/// replied to it.
class PostThread {
  const PostThread({
    this.ancestors = const [],
    this.replies = const [],
    this.more,
  });

  static const empty = PostThread();

  /// Oldest first, ending with the post's direct parent. Without these,
  /// opening a reply shows an answer with no question.
  final List<FeedItem> ancestors;

  final List<ThreadEntry> replies;

  /// Top-level comments the network didn't send.
  final MoreReplies? more;

  bool get isEmpty => ancestors.isEmpty && replies.isEmpty;
}
