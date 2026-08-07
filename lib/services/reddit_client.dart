import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/feed_item.dart';
import '../models/network.dart';
import '../util/text.dart';
import 'source_client.dart';

/// Reddit via the public JSON listing API (no account needed).
///
/// `subreddit` may combine several with '+', e.g. "flutter+androiddev".
class RedditClient extends SourceClient {
  const RedditClient(super.source, super.httpClient);

  /// Reddit turns away clients that don't look like a browser, so present as
  /// one. old.reddit.com serves the same JSON and is markedly less
  /// aggressive about blocking, which is why it's tried as a fallback.
  static const _hosts = ['www.reddit.com', 'old.reddit.com'];

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/124.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  @override
  Future<List<FeedItem>> fetchLatest({int limit = 40}) async {
    final subreddit = source.params['subreddit']!.replaceAll(RegExp(r'^/?r/'), '');
    final sort = source.params['sort'] ?? 'hot';

    http.Response? lastResponse;
    for (final host in _hosts) {
      final res = await httpClient.get(
        Uri.https(host, '/r/$subreddit/$sort.json',
            {'limit': '$limit', 'raw_json': '1'}),
        headers: _headers,
      );
      if (res.statusCode == 200) return _parse(res);
      lastResponse = res;
      // Only a block is worth retrying elsewhere; a 404 means the same
      // thing on every host.
      if (res.statusCode != 403 && res.statusCode != 429) break;
    }

    throw SourceFetchException(
        source.displayName, _explain(lastResponse!.statusCode, subreddit));
  }

  /// Reddit uses the same status code for several very different problems,
  /// so say which one it likely is rather than echoing a bare number.
  static String _explain(int status, String subreddit) => switch (status) {
        403 =>
          'Reddit refused the request for r/$subreddit (403). That subreddit is '
              'usually private, quarantined or banned — or Reddit is temporarily '
              'blocking anonymous access from your network. Public subreddits '
              'normally work on a retry.',
        404 => 'No subreddit called r/$subreddit.',
        429 => 'Reddit is rate limiting right now — try again in a minute.',
        _ => 'HTTP $status from Reddit.',
      };

  List<FeedItem> _parse(http.Response res) {
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final children =
        ((body['data'] as Map<String, dynamic>?)?['children'] as List? ??
            const []);

    return children
        .map((c) => _toItem((c as Map<String, dynamic>)['data']
            as Map<String, dynamic>))
        .toList(growable: false);
  }

  FeedItem _toItem(Map<String, dynamic> post) {
    final images = <String>[];
    final preview = post['preview'] as Map<String, dynamic>?;
    final previewImages = preview?['images'] as List?;
    if (previewImages != null && previewImages.isNotEmpty) {
      final url = ((previewImages.first as Map<String, dynamic>)['source']
          as Map<String, dynamic>?)?['url'] as String?;
      if (url != null) images.add(url);
    } else {
      final direct = post['url_overridden_by_dest'] as String? ?? '';
      if (RegExp(r'\.(png|jpe?g|gif|webp)$').hasMatch(direct)) {
        images.add(direct);
      }
    }

    final selftext = post['selftext'] as String? ?? '';
    final createdUtc = (post['created_utc'] as num?)?.toDouble() ?? 0;

    return FeedItem(
      id: '${source.id}:${post['name'] ?? post['id']}',
      sourceId: source.id,
      network: Network.reddit,
      author: 'u/${post['author'] ?? '[deleted]'}',
      title: htmlToPlainText(post['title'] as String? ?? ''),
      text: selftext.length > 500 ? '${selftext.substring(0, 500)}…' : selftext,
      url: 'https://www.reddit.com${post['permalink'] ?? ''}',
      imageUrls: images,
      likes: post['ups'] as int?,
      replies: post['num_comments'] as int?,
      context: 'r/${post['subreddit'] ?? source.params['subreddit']}',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (createdUtc * 1000).round(),
          isUtc: true),
    );
  }
}
