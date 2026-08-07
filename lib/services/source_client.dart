import 'package:http/http.dart' as http;

import '../models/feed_item.dart';
import '../models/feed_source.dart';
import '../models/network.dart';
import 'bluesky_client.dart';
import 'mastodon_client.dart';
import 'reddit_client.dart';
import 'rss_client.dart';
import 'twitter_client.dart';
import 'twitter_guest_client.dart';
import 'twitter_guest_config.dart';
import 'twitter_guest_session.dart';
import 'twitter_session_store.dart';

/// Fetches the latest posts for one configured [FeedSource].
abstract class SourceClient {
  const SourceClient(this.source, this.httpClient);

  final FeedSource source;
  final http.Client httpClient;

  Future<List<FeedItem>> fetchLatest({int limit = 40});

  /// Replies to [item], flattened with nesting depth. Networks that have no
  /// notion of a thread (RSS) return nothing, which the detail view treats
  /// as "no discussion", not as a failure.
  Future<List<ThreadEntry>> fetchThread(FeedItem item, {int limit = 100}) async =>
      const [];

  /// Twitter sources come in two flavours: [TwitterGuestClient] (anonymous,
  /// no API plan) and [TwitterClient] (official API v2, paid). [twitterConfig]
  /// and [twitterSession] are only consulted for the anonymous path.
  static SourceClient forSource(
    FeedSource source,
    http.Client httpClient, {
    TwitterGuestConfig? twitterConfig,
    TwitterGuestSession? twitterSession,
    TwitterSession? twitterAccount,
  }) =>
      switch (source.network) {
        Network.mastodon => MastodonClient(source, httpClient),
        Network.bluesky => BlueskyClient(source, httpClient),
        Network.reddit => RedditClient(source, httpClient),
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
