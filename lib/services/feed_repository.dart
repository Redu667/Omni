import 'package:http/http.dart' as http;

import '../models/feed_item.dart';
import '../models/feed_source.dart';
import 'source_client.dart';
import 'twitter_guest_config.dart';
import 'twitter_guest_session.dart';
import 'twitter_session_store.dart';

class FeedResult {
  const FeedResult({
    required this.items,
    required this.errors,
    this.cursors = const {},
  });

  final List<FeedItem> items;

  /// Per-source failure messages; the feed still shows what succeeded.
  final List<String> errors;

  /// Where each source got to, keyed by source id. A source missing from
  /// this map has nothing older to offer.
  final Map<String, String> cursors;

  bool get hasMore => cursors.isNotEmpty;
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
  Future<PostThread> fetchThread(
    FeedItem item,
    List<FeedSource> sources, {
    TwitterGuestConfig? twitterConfig,
    TwitterSession? twitterAccount,
  }) async {
    final source = sources.where((s) => s.id == item.sourceId).firstOrNull;
    if (source == null) return PostThread.empty;

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

  /// Fetches one page from every enabled source in parallel and merges them.
  ///
  /// Pass [cursors] from a previous result to fetch the next page; sources
  /// absent from it are skipped, because they have already run out.
  Future<FeedResult> fetchAll(
    List<FeedSource> sources, {
    int limitPerSource = 40,
    TwitterGuestConfig? twitterConfig,
    TwitterSession? twitterAccount,
    Map<String, String>? cursors,
  }) async {
    final loadingMore = cursors != null;
    final enabled = sources
        .where((s) => s.enabled && (!loadingMore || cursors.containsKey(s.id)))
        .toList();

    final errors = <String>[];
    final nextCursors = <String, String>{};

    final results = await Future.wait(enabled.map((source) async {
      try {
        final page = await SourceClient.forSource(
          source,
          _http,
          twitterConfig: twitterConfig,
          twitterSession: _twitterSession,
          twitterAccount: twitterAccount,
        ).fetchPage(limit: limitPerSource, cursor: cursors?[source.id]);

        if (page.nextCursor != null && page.items.isNotEmpty) {
          nextCursors[source.id] = page.nextCursor!;
        }
        return page.items;
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

    return FeedResult(items: merged, errors: errors, cursors: nextCursors);
  }

  void dispose() => _http.close();
}
