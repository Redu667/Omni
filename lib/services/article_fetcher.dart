import 'dart:convert';

import 'package:http/http.dart' as http;

import 'readability.dart';

/// Fetches the article behind a link and extracts its text.
///
/// Only worth doing for feeds that publish a teaser — which is most of
/// them. Results are kept for the session so going back to a post doesn't
/// re-download the page.
class ArticleFetcher {
  ArticleFetcher({http.Client? httpClient, this.maxBytes = 2 * 1024 * 1024})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Pages larger than this are almost never articles, and downloading one
  /// on a phone connection to find that out is rude.
  final int maxBytes;

  final _cache = <String, String>{};

  /// A previously extracted article, if this url has been fetched already.
  String? cached(String url) => _cache[url];

  /// Returns the article text, or throws [ArticleException] with something
  /// worth showing a reader.
  Future<String> fetch(String url) async {
    final hit = _cache[url];
    if (hit != null) return hit;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isScheme('http') && !uri.isScheme('https')) {
      throw ArticleException("That link doesn't go anywhere Omni can read.");
    }

    final http.Response res;
    try {
      res = await _http.get(uri, headers: {
        'User-Agent': 'Omni/1.0 (+feed reader)',
        'Accept': 'text/html,application/xhtml+xml',
      });
    } catch (_) {
      throw ArticleException("Couldn't reach ${uri.host}.");
    }

    if (res.statusCode != 200) {
      throw ArticleException(
          '${uri.host} answered HTTP ${res.statusCode} for that article.');
    }

    final contentType = res.headers['content-type'] ?? '';
    if (contentType.isNotEmpty && !contentType.contains('html')) {
      throw ArticleException('That link is not a web page.');
    }
    if (res.bodyBytes.length > maxBytes) {
      throw ArticleException('That page is too large to read in the app.');
    }

    final article =
        extractArticleText(utf8.decode(res.bodyBytes, allowMalformed: true));
    if (article == null) {
      // Paywalls and app-shell pages both land here, and Omni can't tell
      // them apart — so it says what it knows rather than guessing.
      throw ArticleException(
          "Couldn't find an article on that page. It may be behind a "
          'paywall, or rendered by scripts Omni does not run.');
    }

    _cache[url] = article;
    return article;
  }

  void dispose() => _http.close();
}

class ArticleException implements Exception {
  ArticleException(this.message);
  final String message;

  @override
  String toString() => message;
}
