import 'package:http/http.dart' as http;

import '../models/feed_item.dart';
import '../models/feed_source.dart';
import 'source_client.dart';
import 'twitter_guest_config.dart';
import 'twitter_guest_session.dart';

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

  Future<FeedResult> fetchAll(
    List<FeedSource> sources, {
    int limitPerSource = 40,
    TwitterGuestConfig? twitterConfig,
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
