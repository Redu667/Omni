import 'dart:convert';

import '../models/feed_item.dart';
import '../models/network.dart';
import 'source_client.dart';

/// Twitter/X via the official v2 API.
///
/// Requires a user-supplied bearer token (the free tier does not include
/// read access, so this generally needs a paid API plan). Fetches recent
/// tweets from the configured usernames using the recent-search endpoint.
class TwitterClient extends SourceClient {
  const TwitterClient(super.source, super.httpClient);

  @override
  Future<List<FeedItem>> fetchLatest({int limit = 40}) async {
    final bearer = source.params['bearerToken'];
    if (bearer == null || bearer.isEmpty) {
      throw SourceFetchException(source.displayName, 'no bearer token set');
    }
    final usernames = (source.params['usernames'] ?? '')
        .split(RegExp(r'[,\s]+'))
        .where((u) => u.isNotEmpty)
        .map((u) => u.replaceAll('@', ''))
        .toList();
    if (usernames.isEmpty) {
      throw SourceFetchException(source.displayName, 'no usernames set');
    }

    final query = usernames.map((u) => 'from:$u').join(' OR ');
    final uri = Uri.https('api.x.com', '/2/tweets/search/recent', {
      'query': '($query) -is:retweet',
      'max_results': '${limit.clamp(10, 100)}',
      'tweet.fields': 'created_at,public_metrics,attachments',
      'expansions': 'author_id,attachments.media_keys',
      'user.fields': 'name,username,profile_image_url',
      'media.fields': 'url,preview_image_url,type',
    });

    final res = await httpClient
        .get(uri, headers: {'Authorization': 'Bearer $bearer'});
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw SourceFetchException(source.displayName,
          'token rejected (HTTP ${res.statusCode}) — API read access requires a paid plan');
    }
    if (res.statusCode != 200) {
      throw SourceFetchException(
          source.displayName, 'HTTP ${res.statusCode} from api.x.com');
    }

    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final tweets = body['data'] as List? ?? const [];
    final includes = body['includes'] as Map<String, dynamic>? ?? const {};

    final users = {
      for (final u in (includes['users'] as List? ?? const []))
        (u as Map<String, dynamic>)['id'] as String: u,
    };
    final media = {
      for (final m in (includes['media'] as List? ?? const []))
        (m as Map<String, dynamic>)['media_key'] as String: m,
    };

    return tweets
        .map((t) => _toItem(t as Map<String, dynamic>, users, media))
        .toList(growable: false);
  }

  FeedItem _toItem(
    Map<String, dynamic> tweet,
    Map<String, Map<String, dynamic>> users,
    Map<String, Map<String, dynamic>> media,
  ) {
    final user = users[tweet['author_id']] ?? const <String, dynamic>{};
    final username = user['username'] as String? ?? '';
    final metrics =
        tweet['public_metrics'] as Map<String, dynamic>? ?? const {};

    final images = <String>[];
    final mediaKeys = ((tweet['attachments'] as Map<String, dynamic>?)?['media_keys']
            as List? ??
        const []);
    for (final key in mediaKeys) {
      final m = media[key];
      final url = (m?['url'] ?? m?['preview_image_url']) as String?;
      if (url != null) images.add(url);
    }

    return FeedItem(
      id: '${source.id}:${tweet['id']}',
      sourceId: source.id,
      network: Network.twitter,
      author: user['name'] as String? ?? username,
      handle: '@$username',
      avatarUrl: user['profile_image_url'] as String?,
      text: tweet['text'] as String? ?? '',
      url: username.isNotEmpty
          ? 'https://x.com/$username/status/${tweet['id']}'
          : null,
      imageUrls: images,
      likes: metrics['like_count'] as int?,
      reposts: metrics['retweet_count'] as int?,
      replies: metrics['reply_count'] as int?,
      context: source.displayName,
      createdAt:
          DateTime.tryParse(tweet['created_at'] as String? ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
    );
  }
}
