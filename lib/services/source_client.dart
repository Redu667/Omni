import 'package:http/http.dart' as http;

import '../models/feed_item.dart';
import '../models/feed_source.dart';
import '../models/network.dart';
import 'bluesky_client.dart';
import 'mastodon_client.dart';
import 'reddit_client.dart';
import 'rss_client.dart';
import 'twitter_client.dart';

/// Fetches the latest posts for one configured [FeedSource].
abstract class SourceClient {
  const SourceClient(this.source, this.httpClient);

  final FeedSource source;
  final http.Client httpClient;

  Future<List<FeedItem>> fetchLatest({int limit = 40});

  static SourceClient forSource(FeedSource source, http.Client httpClient) =>
      switch (source.network) {
        Network.mastodon => MastodonClient(source, httpClient),
        Network.bluesky => BlueskyClient(source, httpClient),
        Network.reddit => RedditClient(source, httpClient),
        Network.twitter => TwitterClient(source, httpClient),
        Network.rss => RssClient(source, httpClient),
      };
}

class SourceFetchException implements Exception {
  SourceFetchException(this.sourceName, this.message);
  final String sourceName;
  final String message;

  @override
  String toString() => '$sourceName: $message';
}
