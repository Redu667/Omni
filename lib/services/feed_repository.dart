import 'package:http/http.dart' as http;

import '../models/feed_item.dart';
import '../models/feed_source.dart';
import 'bluesky_session.dart';
import 'reddit_auth.dart';
import 'resilient_client.dart';
import 'source_client.dart';
import 'source_health.dart';
import 'twitter_guest_config.dart';
import 'twitter_guest_session.dart';
import 'twitter_session_store.dart';

class FeedResult {
  const FeedResult({
    required this.items,
    required this.errors,
    this.cursors = const {},
    this.staleSourceIds = const {},
  });

  final List<FeedItem> items;

  /// Per-source failure messages; the feed still shows what succeeded.
  final List<String> errors;

  /// Where each source got to, keyed by source id. A source missing from
  /// this map has nothing older to offer.
  final Map<String, String> cursors;

  /// Sources whose posts in [items] came from the last successful fetch
  /// rather than this one — they failed, but their content is still shown.
  final Set<String> staleSourceIds;

  bool get hasMore => cursors.isNotEmpty;
}

/// Fans out to every enabled source in parallel and merges the results
/// into one reverse-chronological timeline.
class FeedRepository {
  FeedRepository({http.Client? httpClient, RedditAuth? redditAuth})
      : _http = httpClient ?? ResilientClient(),
        _redditAuth = redditAuth;

  final http.Client _http;

  /// Null means Reddit is read anonymously. Injected rather than created
  /// here so tests never reach for platform storage.
  final RedditAuth? _redditAuth;

  /// The most recent successful page from each source. A source that starts
  /// failing keeps showing these rather than disappearing from the
  /// timeline, which is what used to happen on a single 403.
  final _lastGood = <String, List<FeedItem>>{};

  final _health = <String, SourceHealth>{};

  SourceHealth healthOf(String sourceId) =>
      _health[sourceId] ?? const SourceHealth();

  Map<String, SourceHealth> get health => Map.unmodifiable(_health);

  /// Shared across refreshes so one anonymous X session serves every
  /// Twitter source instead of activating a token per account.
  final _twitterSession = TwitterGuestSession();

  /// Likewise for Bluesky: one sign-in serves every Bluesky source and
  /// survives between refreshes.
  final _blueskySessions = BlueskySessions();

  /// Replies to [item], asked of whichever source produced it.
  Future<PostThread> fetchThread(
    FeedItem item,
    List<FeedSource> sources, {
    TwitterGuestConfig? twitterConfig,
    TwitterSession? twitterAccount,
    String? sort,
  }) async {
    final client = _clientFor(item, sources,
        twitterConfig: twitterConfig, twitterAccount: twitterAccount);
    if (client == null) return PostThread.empty;
    return client.fetchThread(item, sort: sort);
  }

  /// The replies a network held back — see [MoreReplies].
  Future<List<ThreadEntry>> fetchMoreReplies(
    FeedItem item,
    MoreReplies more,
    List<FeedSource> sources, {
    TwitterGuestConfig? twitterConfig,
    TwitterSession? twitterAccount,
    String? sort,
  }) async {
    final client = _clientFor(item, sources,
        twitterConfig: twitterConfig, twitterAccount: twitterAccount);
    if (client == null) return const [];
    return client.fetchMoreReplies(item, more, sort: sort);
  }

  /// The comment orderings [item]'s network offers.
  Map<String, String> commentSorts(
    FeedItem item,
    List<FeedSource> sources, {
    TwitterGuestConfig? twitterConfig,
  }) =>
      _clientFor(item, sources, twitterConfig: twitterConfig)?.commentSorts ??
      const {};

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
      blueskySessions: _blueskySessions,
      twitterAccount: twitterAccount,
      redditAuth: _redditAuth,
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
    final stale = <String>{};
    final now = DateTime.now();

    final results = await Future.wait(enabled.map((source) async {
      try {
        final page = await SourceClient.forSource(
          source,
          _http,
          twitterConfig: twitterConfig,
          twitterSession: _twitterSession,
          blueskySessions: _blueskySessions,
          twitterAccount: twitterAccount,
          redditAuth: _redditAuth,
        ).fetchPage(limit: limitPerSource, cursor: cursors?[source.id]);

        if (page.nextCursor != null && page.items.isNotEmpty) {
          nextCursors[source.id] = page.nextCursor!;
        }
        _health[source.id] = healthOf(source.id).succeeded(now);
        if (!loadingMore) _lastGood[source.id] = page.items;
        return page.items;
      } on SourceFetchException catch (e) {
        errors.add(e.toString());
        _health[source.id] = healthOf(source.id).failed(e.message);
      } catch (e) {
        errors.add('${source.displayName}: ${e.toString()}');
        _health[source.id] = healthOf(source.id).failed(e.toString());
      }

      // Show what this source last gave us rather than dropping it out of
      // the timeline entirely. Paging is exempt: repeating the previous
      // page as "older posts" would just duplicate them.
      final previous = loadingMore ? null : _lastGood[source.id];
      if (previous != null && previous.isNotEmpty) {
        stale.add(source.id);
        return previous;
      }
      return const <FeedItem>[];
    }));

    final seen = <String>{};
    final merged = <FeedItem>[
      for (final list in results)
        for (final item in list)
          if (seen.add(item.id)) item,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return FeedResult(
      items: merged,
      errors: errors,
      cursors: nextCursors,
      staleSourceIds: stale,
    );
  }

  void dispose() => _http.close();
}
