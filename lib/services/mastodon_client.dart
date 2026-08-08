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

  @override
  Future<List<ThreadEntry>> fetchThread(FeedItem item, {int limit = 100}) async {
    final statusId = item.nativeId;
    if (statusId == null) return const [];

    final instance =
        source.params['instance']!.replaceAll(RegExp(r'^https?://'), '');
    final token = source.params['accessToken'];

    final res = await httpClient.get(
      Uri.https(instance, '/api/v1/statuses/$statusId/context'),
      headers: {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );
    if (res.statusCode != 200) return const [];

    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final descendants =
        (body['descendants'] as List? ?? const []).cast<Map<String, dynamic>>();

    // Mastodon returns a flat list; depth comes from following in_reply_to_id
    // back towards the post being viewed.
    final depths = <String, int>{statusId: -1};
    final entries = <ThreadEntry>[];
    for (final status in descendants.take(limit)) {
      final id = status['id'] as String?;
      if (id == null) continue;
      final parent = status['in_reply_to_id'] as String?;
      final depth = (depths[parent] ?? -1) + 1;
      depths[id] = depth;
      entries.add(ThreadEntry(depth: depth, item: _toItem(status)));
    }
    return entries;
  }

  @override
  bool get supportsAuthorFeed => true;

  @override
  Future<List<FeedItem>> fetchAuthorPosts(FeedItem item, {int limit = 40}) async {
    final acct = item.handle?.replaceFirst(RegExp(r'^@'), '');
    if (acct == null || acct.isEmpty) return const [];

    final instance =
        source.params['instance']!.replaceAll(RegExp(r'^https?://'), '');
    final token = source.params['accessToken'];
    final headers = {
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    // A handle has to be resolved to a numeric id before statuses can be
    // fetched; for remote accounts this also pulls them into the instance.
    final lookup = await httpClient.get(
      Uri.https(instance, '/api/v1/accounts/lookup', {'acct': acct}),
      headers: headers,
    );
    if (lookup.statusCode != 200) {
      throw SourceFetchException(
          source.displayName, 'Could not find @$acct on $instance.');
    }
    final accountId =
        (jsonDecode(utf8.decode(lookup.bodyBytes)) as Map<String, dynamic>)['id']
            as String?;
    if (accountId == null) return const [];

    final res = await httpClient.get(
      Uri.https(instance, '/api/v1/accounts/$accountId/statuses',
          {'limit': '$limit', 'exclude_replies': 'false'}),
      headers: headers,
    );
    if (res.statusCode != 200) {
      throw SourceFetchException(
          source.displayName, 'HTTP ${res.statusCode} loading @$acct.');
    }

    return (jsonDecode(utf8.decode(res.bodyBytes)) as List)
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
      nativeId: s['id'] as String?,
      contentWarning: (s['spoiler_text'] as String?)?.trim().isNotEmpty == true
          ? (s['spoiler_text'] as String).trim()
          : null,
      sensitive: s['sensitive'] as bool? ?? false,
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
