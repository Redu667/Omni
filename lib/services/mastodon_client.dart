import 'dart:convert';

import '../models/feed_item.dart';
import '../models/network.dart';
import '../util/text.dart';
import 'source_client.dart';

/// Mastodon timelines.
///
/// Four kinds, in the order they're checked:
///  - `hashtag`: a tag timeline, public and needing no account.
///  - `list`: one of the account's own lists, which does need a token.
///  - a token, and neither of the above: the account's home timeline.
///  - nothing: the instance's public (federated or local) timeline.
class MastodonClient extends SourceClient {
  const MastodonClient(super.source, super.httpClient);

  @override
  Future<SourcePage> fetchPage({int limit = 40, String? cursor}) async {
    final instance = source.params['instance']!.replaceAll(RegExp(r'^https?://'), '');
    final token = source.params['accessToken'];
    final local = source.params['local'] == 'true';
    final hashtag = source.params['hashtag']?.replaceFirst(RegExp(r'^#'), '');
    final list = source.params['list'];

    // Mastodon pages by asking for statuses older than an id.
    final query = {
      'limit': '$limit',
      if (cursor != null) 'max_id': cursor,
    };

    final Uri uri;
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    if (hashtag != null && hashtag.isNotEmpty) {
      // Tag timelines are public, so this works signed in or not.
      uri = Uri.https(instance, '/api/v1/timelines/tag/$hashtag',
          {...query, if (local) 'local': 'true'});
    } else if (list != null && list.isNotEmpty) {
      if (headers.isEmpty) {
        throw SourceFetchException(source.displayName,
            'lists are private — sign in to this instance to read one');
      }
      uri = Uri.https(instance, '/api/v1/timelines/list/$list', query);
    } else if (headers.isNotEmpty) {
      uri = Uri.https(instance, '/api/v1/timelines/home', query);
    } else {
      uri = Uri.https(instance, '/api/v1/timelines/public',
          {...query, if (local) 'local': 'true'});
    }

    final res = await httpClient.get(uri, headers: headers);
    if (res.statusCode != 200) {
      throw SourceFetchException(
          source.displayName, _explain(res.statusCode, instance));
    }

    final statuses = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    final items = statuses
        .map((s) => _toItem(s as Map<String, dynamic>))
        .toList(growable: false);

    // A short page means the end; otherwise page from the oldest id here.
    final oldestId = statuses.isEmpty
        ? null
        : (statuses.last as Map<String, dynamic>)['id'] as String?;
    return SourcePage(
      items: items,
      nextCursor: statuses.length < limit ? null : oldestId,
    );
  }

  /// A hashtag or list that doesn't exist 404s exactly like a wrong
  /// instance, so name the likely cause instead of the number.
  String _explain(int status, String instance) {
    final what = source.params['hashtag'] != null
        ? 'hashtag'
        : source.params['list'] != null
            ? 'list'
            : null;
    return switch (status) {
      404 when what != null => 'No such $what on $instance.',
      401 || 403 when what == 'list' =>
        'That list belongs to another account, or the sign-in has expired.',
      _ => 'HTTP $status from $instance',
    };
  }

  /// The account's own lists, as `id: title` — used to offer a choice
  /// rather than making the user find a numeric id.
  Future<Map<String, String>> fetchLists() async {
    final instance =
        source.params['instance']!.replaceAll(RegExp(r'^https?://'), '');
    final token = source.params['accessToken'];
    if (token == null || token.isEmpty) return const {};

    final res = await httpClient.get(
      Uri.https(instance, '/api/v1/lists'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) return const {};

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! List) return const {};
    return {
      for (final entry in decoded.cast<Map<String, dynamic>>())
        if (entry['id'] is String)
          entry['id'] as String: entry['title'] as String? ?? 'Untitled list',
    };
  }

  @override
  Future<PostThread> fetchThread(FeedItem item,
      {int limit = 100, String? sort}) async {
    final statusId = item.nativeId;
    if (statusId == null) return PostThread.empty;

    final instance =
        source.params['instance']!.replaceAll(RegExp(r'^https?://'), '');
    final token = source.params['accessToken'];

    final res = await httpClient.get(
      Uri.https(instance, '/api/v1/statuses/$statusId/context'),
      headers: {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );
    if (res.statusCode != 200) return PostThread.empty;

    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final descendants =
        (body['descendants'] as List? ?? const []).cast<Map<String, dynamic>>();
    // The context call returns these too; they were previously thrown away,
    // which left a reply displayed with nothing to reply to.
    final ancestors =
        (body['ancestors'] as List? ?? const []).cast<Map<String, dynamic>>();

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

    return PostThread(
      ancestors: ancestors.map(_toItem).toList(growable: false),
      replies: entries,
    );
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

  /// Mastodon sends custom emoji as a list of `{shortcode, url}`; the UI
  /// wants to look them up by code.
  static Map<String, String> _emojiMap(Object? raw) {
    if (raw is! List) return const {};
    return {
      for (final e in raw.whereType<Map<String, dynamic>>())
        if (e['shortcode'] is String && e['url'] is String)
          e['shortcode'] as String: e['url'] as String,
    };
  }

  /// Mastodon attachments are `image`, `video`, `gifv` (a silent looping
  /// clip) or `audio`. Video was previously dropped outright, which quietly
  /// turned a video post into an empty one.
  static MediaItem? _mediaFrom(Map<String, dynamic> m) {
    final type = m['type'] as String?;
    final alt = m['description'] as String?;
    final preview = m['preview_url'] as String?;
    final url = m['url'] as String?;

    return switch (type) {
      'image' when preview != null => MediaItem(url: preview, alt: alt),
      'video' || 'gifv' when url != null => MediaItem(
          url: url,
          alt: alt,
          kind: type == 'gifv' ? MediaKind.gif : MediaKind.video,
          thumbnailUrl: preview,
          durationSeconds:
              (_dig(m, ['meta', 'original', 'duration']) as num?)?.round(),
        ),
      _ => null,
    };
  }

  static Object? _dig(Map<String, dynamic> from, List<String> path) {
    Object? node = from;
    for (final key in path) {
      if (node is! Map) return null;
      node = node[key];
    }
    return node;
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
      poll: _pollFrom(s['poll'] as Map<String, dynamic>?),
      linkCard: _cardFrom(s['card'] as Map<String, dynamic>?),
      contentWarning: (s['spoiler_text'] as String?)?.trim().isNotEmpty == true
          ? (s['spoiler_text'] as String).trim()
          : null,
      sensitive: s['sensitive'] as bool? ?? false,
      media: [
        for (final m in media)
          if (_mediaFrom(m) case final attachment?) attachment,
      ],
      repostedBy: repostedBy,
      // Both the post and the author can use custom emoji, and the author's
      // are what make a display name render as intended.
      emojis: {
        ..._emojiMap(account['emojis']),
        ..._emojiMap(s['emojis']),
      },
      likes: s['favourites_count'] as int?,
      reposts: s['reblogs_count'] as int?,
      replies: s['replies_count'] as int?,
      context: source.displayName,
      createdAt:
          DateTime.tryParse(s['created_at'] as String? ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
    );
  }

  /// Poll posts carry their question in the body and their options here;
  /// without this they render as a question with no answers.
  static Poll? _pollFrom(Map<String, dynamic>? poll) {
    if (poll == null) return null;
    final options = (poll['options'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    if (options.isEmpty) return null;

    return Poll(
      options: [
        for (final o in options)
          PollOption(
            title: o['title'] as String? ?? '',
            votes: o['votes_count'] as int? ?? 0,
          ),
      ],
      totalVotes: poll['votes_count'] as int? ?? 0,
      expiresAt: DateTime.tryParse(poll['expires_at'] as String? ?? ''),
      expired: poll['expired'] as bool? ?? false,
    );
  }

  static LinkCard? _cardFrom(Map<String, dynamic>? card) {
    final url = card?['url'] as String?;
    if (card == null || url == null) return null;
    return LinkCard(
      url: url,
      title: card['title'] as String?,
      description: card['description'] as String?,
      imageUrl: card['image'] as String?,
    );
  }

  static String _displayName(Map<String, dynamic> account) {
    final name = account['display_name'] as String? ?? '';
    return name.isNotEmpty ? name : (account['username'] as String? ?? '?');
  }
}
