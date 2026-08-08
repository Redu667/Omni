import 'package:http/http.dart' as http;

import '../models/feed_item.dart';
import '../models/feed_source.dart';
import 'source_client.dart';
import 'twitter_guest_config.dart';
import 'twitter_guest_session.dart';
import 'twitter_session_store.dart';

class FeedResult {
  const FeedResult({required this.items, required this.errors});

  final List<FeedItem> items;

  /// Per-source failure messages; the feed still shows what succeeded.
  final List<String> errors;
}

/// Fans out to every enabled source in parallel and merges the results
/// into one reverse-chronological timeline.
class FeedRepository {
  FeedRepository({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Shared across refreshes so one anonymous X session serves every
  /// Twitter source instead of activating a token per account.
  final _twitterSession = TwitterGuestSession();

  /// Replies to [item], asked of whichever source produced it.
  Future<List<ThreadEntry>> fetchThread(
    FeedItem item,
    List<FeedSource> sources, {
    TwitterGuestConfig? twitterConfig,
    TwitterSession? twitterAccount,
  }) async {
    final source = sources.where((s) => s.id == item.sourceId).firstOrNull;
    if (source == null) return const [];

    return SourceClient.forSource(
      source,
      _http,
      twitterConfig: twitterConfig,
      twitterSession: _twitterSession,
      twitterAccount: twitterAccount,
    ).fetchThread(item);
  }

  /// Recent posts by whoever wrote [item], asked of its own source.
  Future<List<FeedItem>> fetchAuthorPosts(
    FeedItem item,
    List<FeedSource> sources, {
    TwitterGuestConfig? twitterConfig,
    TwitterSession? twitterAccount,
  }) async {
    final client = _clientFor(item, sources,
        twitterConfig: twitterConfig, twitterAccount: twitterAccount);
    if (client == null) return const [];
    return client.fetchAuthorPosts(item);
  }

  bool supportsAuthorFeed(
    FeedItem item,
    List<FeedSource> sources, {
    TwitterGuestConfig? twitterConfig,
  }) =>
      _clientFor(item, sources, twitterConfig: twitterConfig)
          ?.supportsAuthorFeed ??
      false;

  SourceClient? _clientFor(
    FeedItem item,
    List<FeedSource> sources, {
    TwitterGuestConfig? twitterConfig,
    TwitterSession? twitterAccount,
  }) {
    final source = sources.where((s) => s.id == item.sourceId).firstOrNull;
    if (source == null) return null;
    return SourceClient.forSource(
      source,
      _http,
      twitterConfig: twitterConfig,
      twitterSession: _twitterSession,
      twitterAccount: twitterAccount,
    );
  }

  Future<FeedResult> fetchAll(
    List<FeedSource> sources, {
    int limitPerSource = 40,
    TwitterGuestConfig? twitterConfig,
    TwitterSession? twitterAccount,
  }) async {
    final enabled = sources.where((s) => s.enabled).toList();
    final errors = <String>[];

    final results = await Future.wait(enabled.map((source) async {
      try {
        return await SourceClient.forSource(
          source,
          _http,
          twitterConfig: twitterConfig,
          twitterSession: _twitterSession,
          twitterAccount: twitterAccount,
        ).fetchLatest(limit: limitPerSource);
      } on SourceFetchException catch (e) {
        errors.add(e.toString());
      } catch (e) {
        errors.add('${source.displayName}: ${e.toString()}');
      }
      return const <FeedItem>[];
    }));

    final seen = <String>{};
    final merged = <FeedItem>[
      for (final list in results)
        for (final item in list)
          if (seen.add(item.id)) item,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return FeedResult(items: merged, errors: errors);
  }

  void dispose() => _http.close();
}
