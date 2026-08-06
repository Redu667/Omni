import 'dart:convert';

import '../models/feed_item.dart';
import '../models/network.dart';
import '../util/text.dart';
import 'source_client.dart';

/// Reddit via the public JSON listing API (no account needed).
///
/// `subreddit` may combine several with '+', e.g. "flutter+androiddev".
class RedditClient extends SourceClient {
  const RedditClient(super.source, super.httpClient);

  @override
  Future<List<FeedItem>> fetchLatest({int limit = 40}) async {
    final subreddit = source.params['subreddit']!.replaceAll(RegExp(r'^/?r/'), '');
    final sort = source.params['sort'] ?? 'hot';

    final uri = Uri.https('www.reddit.com', '/r/$subreddit/$sort.json',
        {'limit': '$limit', 'raw_json': '1'});
    final res = await httpClient.get(uri, headers: {
      'User-Agent': 'android:dev.omni:v0.1.0 (unified feed reader)',
    });
    if (res.statusCode != 200) {
      throw SourceFetchException(
          source.displayName, 'HTTP ${res.statusCode} from reddit.com');
    }

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
