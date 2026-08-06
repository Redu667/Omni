import 'dart:convert';

import '../models/feed_item.dart';
import '../models/network.dart';
import '../util/text.dart';
import 'source_client.dart';

/// Mastodon timelines.
///
/// With an access token, fetches the account's home timeline; without one,
/// the instance's public (federated or local) timeline.
class MastodonClient extends SourceClient {
  const MastodonClient(super.source, super.httpClient);

  @override
  Future<List<FeedItem>> fetchLatest({int limit = 40}) async {
    final instance = source.params['instance']!.replaceAll(RegExp(r'^https?://'), '');
    final token = source.params['accessToken'];
    final local = source.params['local'] == 'true';

    final Uri uri;
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      uri = Uri.https(instance, '/api/v1/timelines/home', {'limit': '$limit'});
      headers['Authorization'] = 'Bearer $token';
    } else {
      uri = Uri.https(instance, '/api/v1/timelines/public',
          {'limit': '$limit', if (local) 'local': 'true'});
    }

    final res = await httpClient.get(uri, headers: headers);
    if (res.statusCode != 200) {
      throw SourceFetchException(
          source.displayName, 'HTTP ${res.statusCode} from $instance');
    }

    final statuses = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return statuses
        .map((s) => _toItem(s as Map<String, dynamic>))
        .toList(growable: false);
  }

  FeedItem _toItem(Map<String, dynamic> status) {
    String? repostedBy;
    var s = status;
    if (status['reblog'] != null) {
      repostedBy = _displayName(status['account'] as Map<String, dynamic>);
      s = status['reblog'] as Map<String, dynamic>;
    }

    final account = s['account'] as Map<String, dynamic>;
    final media = (s['media_attachments'] as List? ?? const [])
        .cast<Map<String, dynamic>>();

    return FeedItem(
      id: '${source.id}:${status['id']}',
      sourceId: source.id,
      network: Network.mastodon,
      author: _displayName(account),
      handle: '@${account['acct']}',
      avatarUrl: account['avatar'] as String?,
      text: htmlToPlainText(s['content'] as String? ?? ''),
      url: (s['url'] ?? s['uri']) as String?,
      imageUrls: [
        for (final m in media)
          if (m['type'] == 'image' && m['preview_url'] != null)
            m['preview_url'] as String,
      ],
      repostedBy: repostedBy,
      likes: s['favourites_count'] as int?,
      reposts: s['reblogs_count'] as int?,
      replies: s['replies_count'] as int?,
      context: source.displayName,
      createdAt:
          DateTime.tryParse(s['created_at'] as String? ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
    );
  }

  static String _displayName(Map<String, dynamic> account) {
    final name = account['display_name'] as String? ?? '';
    return name.isNotEmpty ? name : (account['username'] as String? ?? '?');
  }
}
