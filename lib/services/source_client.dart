import 'package:http/http.dart' as http;

import '../models/feed_item.dart';
import '../models/feed_source.dart';
import '../models/network.dart';
import 'bluesky_client.dart';
import 'bluesky_session.dart';
import 'mastodon_client.dart';
import 'reddit_auth.dart';
import 'reddit_client.dart';
import 'rss_client.dart';
import 'twitter_client.dart';
import 'twitter_guest_client.dart';
import 'twitter_guest_config.dart';
import 'twitter_guest_session.dart';
import 'twitter_session_store.dart';

/// One page of posts, plus whatever the network needs to be asked for the
/// next one. Every network spells its cursor differently — Mastodon wants
/// the oldest id, Reddit a fullname, Bluesky and X an opaque token — so the
/// value is only ever handed back to the client that produced it.
class SourcePage {
  const SourcePage({required this.items, this.nextCursor});

  const SourcePage.last(this.items) : nextCursor = null;

  final List<FeedItem> items;

  /// Null when there is nothing older to fetch.
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// Fetches the latest posts for one configured [FeedSource].
abstract class SourceClient {
  const SourceClient(this.source, this.httpClient);

  final FeedSource source;
  final http.Client httpClient;

  /// Fetches a page. [cursor] is null for the newest posts, otherwise a value
  /// this same client returned earlier.
  Future<SourcePage> fetchPage({int limit = 40, String? cursor});

  /// The newest page only — most callers want this.
  Future<List<FeedItem>> fetchLatest({int limit = 40}) async =>
      (await fetchPage(limit: limit)).items;

  /// The conversation around [item] — what it replied to, and the replies
  /// beneath it. Networks with no notion of a thread (RSS) return nothing,
  /// which the detail view treats as "no discussion", not as a failure.
  ///
  /// [sort] is one of [commentSorts]; networks that don't offer a choice
  /// ignore it.
  Future<PostThread> fetchThread(FeedItem item,
          {int limit = 100, String? sort}) async =>
      PostThread.empty;

  /// The comment orderings this network offers, as `value: label`. Empty
  /// where there's nothing to choose, which is how the UI decides whether to
  /// show a sort control at all.
  Map<String, String> get commentSorts => const {};

  /// Fetches replies the network held back — see [MoreReplies]. Returns them
  /// flattened, already at the right depth.
  Future<List<ThreadEntry>> fetchMoreReplies(
          FeedItem item, MoreReplies more, {String? sort}) async =>
      const [];

  /// Posts matching [query], asked of the network rather than of what's
  /// already loaded. Networks with no search API return nothing.
  Future<List<FeedItem>> search(String query, {int limit = 40}) async =>
      const [];

  /// Whether [search] can do anything here, so the UI only offers to look
  /// somewhere that can be looked.
  bool get supportsSearch => false;

  /// Recent posts by whoever wrote [item]. Networks with no concept of an
  /// author feed (RSS) return nothing.
  Future<List<FeedItem>> fetchAuthorPosts(FeedItem item, {int limit = 40}) async =>
      const [];

  /// Whether [fetchAuthorPosts] can do anything for this network, so the UI
  /// only offers a profile where one exists.
  bool get supportsAuthorFeed => false;

  /// Twitter sources come in two flavours: [TwitterGuestClient] (anonymous,
  /// no API plan) and [TwitterClient] (official API v2, paid). [twitterConfig]
  /// and [twitterSession] are only consulted for the anonymous path.
  static SourceClient forSource(
    FeedSource source,
    http.Client httpClient, {
    TwitterGuestConfig? twitterConfig,
    TwitterGuestSession? twitterSession,
    TwitterSession? twitterAccount,
    RedditAuth? redditAuth,
    BlueskySessions? blueskySessions,
  }) =>
      switch (source.network) {
        Network.mastodon => MastodonClient(source, httpClient),
        Network.bluesky => BlueskyClient(source, httpClient,
            sessions: blueskySessions ?? BlueskySessions()),
        Network.reddit => RedditClient(source, httpClient, auth: redditAuth),
        Network.rss => RssClient(source, httpClient),
        Network.twitter => source.params['mode'] == 'official'
            ? TwitterClient(source, httpClient)
            : TwitterGuestClient(
                source,
                httpClient,
                config: twitterConfig ?? TwitterGuestConfig.defaults,
                session: twitterSession ?? TwitterGuestSession(),
                account: twitterAccount,
              ),
      };
}

class SourceFetchException implements Exception {
  SourceFetchException(this.sourceName, this.message);
  final String sourceName;
  final String message;

  @override
  String toString() => '$sourceName: $message';
}
