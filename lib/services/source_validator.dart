import 'package:http/http.dart' as http;

import '../models/feed_source.dart';
import '../models/network.dart';
import 'feed_discovery.dart';
import 'source_client.dart';

/// Test-fetches a source before it's saved, so misconfiguration fails at
/// add time with a clear message instead of silently later.
class SourceValidator {
  SourceValidator({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Returns the source (possibly fixed up — e.g. an RSS source whose URL
  /// pointed at an HTML page gets swapped for the page's advertised feed).
  /// Throws [SourceFetchException] with a user-readable message on failure.
  Future<FeedSource> validate(FeedSource source) async {
    try {
      await SourceClient.forSource(source, _http).fetchLatest(limit: 5);
      return source;
    } on SourceFetchException {
      if (source.network == Network.rss) {
        final discovered = await discoverFeedUrl(_http, source.params['url']!);
        if (discovered != null && discovered != source.params['url']) {
          final fixed = FeedSource(
            id: source.id,
            network: source.network,
            displayName: Uri.tryParse(discovered)?.host ?? source.displayName,
            params: {...source.params, 'url': discovered},
          );
          await SourceClient.forSource(fixed, _http).fetchLatest(limit: 5);
          return fixed;
        }
      }
      rethrow;
    }
  }

  void dispose() => _http.close();
}
