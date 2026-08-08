import 'dart:convert';

import '../models/feed_item.dart';
import '../models/network.dart';
import 'source_client.dart';

/// Bluesky (AT Protocol).
///
/// Two modes:
///  - `handle` only: a user's public author feed, no login required.
///  - `identifier` + `appPassword`: signs in and fetches the home timeline.
class BlueskyClient extends SourceClient {
  const BlueskyClient(super.source, super.httpClient);

  /// Labels Bluesky's own moderation treats as adult content.
  static const _adultLabels = {
    'porn',
    'sexual',
    'nudity',
    'graphic-media',
    'gore',
    'nsfl',
  };

  static String _labelLabel(String val) => switch (val) {
        'porn' || 'sexual' => 'Adult content',
        'nudity' => 'Nudity',
        'graphic-media' || 'gore' || 'nsfl' => 'Graphic media',
        _ => 'Labelled: $val',
      };

  static const _publicHost = 'public.api.bsky.app';
  static const _authHost = 'bsky.social';

  @override
  Future<SourcePage> fetchPage({int limit = 40, String? cursor}) async {
    final identifier = source.params['identifier'];
    final appPassword = source.params['appPassword'];

    final paging = {
      'limit': '$limit',
      if (cursor != null) 'cursor': cursor,
    };

    final ({List feed, String? cursor}) result;
    if (identifier != null &&
        identifier.isNotEmpty &&
        appPassword != null &&
        appPassword.isNotEmpty) {
      final jwt = await _createSession(identifier, appPassword);
      result = await _getFeed(
        Uri.https(_authHost, '/xrpc/app.bsky.feed.getTimeline', paging),
        headers: {'Authorization': 'Bearer $jwt'},
      );
    } else {
      final handle =
          (source.params['handle'] ?? '').replaceAll(RegExp(r'^@'), '');
      if (handle.isEmpty) {
        throw SourceFetchException(
            source.displayName, 'no handle or credentials configured');
      }
      result = await _getFeed(
        Uri.https(_publicHost, '/xrpc/app.bsky.feed.getAuthorFeed',
            {'actor': handle, ...paging}),
      );
    }

    return SourcePage(
      items: result.feed
          .map((e) => _toItem(e as Map<String, dynamic>))
          .toList(growable: false),
      // Bluesky keeps returning a cursor past the end, so an empty page is
      // the real signal that there is nothing more.
      nextCursor: result.feed.isEmpty ? null : result.cursor,
    );
  }

  Future<String> _createSession(String identifier, String appPassword) async {
    final res = await httpClient.post(
      Uri.https(_authHost, '/xrpc/com.atproto.server.createSession'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'identifier': identifier, 'password': appPassword}),
    );
    if (res.statusCode != 200) {
      throw SourceFetchException(
          source.displayName, 'sign-in failed (HTTP ${res.statusCode})');
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['accessJwt']
        as String;
  }

  Future<({List feed, String? cursor})> _getFeed(Uri uri,
      {Map<String, String>? headers}) async {
    final res = await httpClient.get(uri, headers: headers);
    if (res.statusCode != 200) {
      throw SourceFetchException(
          source.displayName, 'HTTP ${res.statusCode} from ${uri.host}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (
      feed: body['feed'] as List? ?? const [],
      cursor: body['cursor'] as String?,
    );
  }

  @override
  bool get supportsAuthorFeed => true;

  @override
  Future<List<FeedItem>> fetchAuthorPosts(FeedItem item, {int limit = 40}) async {
    final handle = item.handle?.replaceFirst(RegExp(r'^@'), '');
    if (handle == null || handle.isEmpty) return const [];

    final result = await _getFeed(
      Uri.https(_publicHost, '/xrpc/app.bsky.feed.getAuthorFeed',
          {'actor': handle, 'limit': '$limit'}),
    );
    return result.feed
        .map((e) => _toItem(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<PostThread> fetchThread(FeedItem item, {int limit = 100}) async {
    final uri = item.nativeId;
    if (uri == null) return PostThread.empty;

    final res = await httpClient.get(
      Uri.https(_publicHost, '/xrpc/app.bsky.feed.getPostThread',
          {'uri': uri, 'depth': '6', 'parentHeight': '10'}),
    );
    if (res.statusCode != 200) return PostThread.empty;

    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final thread = body['thread'] as Map<String, dynamic>?;
    if (thread == null) return PostThread.empty;

    final entries = <ThreadEntry>[];
    _collectReplies(thread['replies'] as List?, 0, entries, limit);

    // Walk up the parent chain, then reverse so it reads oldest first.
    final ancestors = <FeedItem>[];
    var parent = thread['parent'] as Map<String, dynamic>?;
    while (parent != null && parent['post'] != null && ancestors.length < 20) {
      ancestors.add(_toItem({'post': parent['post']}));
      parent = parent['parent'] as Map<String, dynamic>?;
    }

    return PostThread(
      ancestors: ancestors.reversed.toList(growable: false),
      replies: entries,
    );
  }

  /// Bluesky nests replies inside each post, so flatten depth-first.
  void _collectReplies(
      List? replies, int depth, List<ThreadEntry> out, int limit) {
    for (final reply in (replies ?? const []).cast<Map<String, dynamic>>()) {
      if (out.length >= limit) return;
      // Blocked and deleted posts come back as stubs with no `post`.
      if (reply['post'] == null) continue;

      out.add(ThreadEntry(depth: depth, item: _toItem({'post': reply['post']})));
      _collectReplies(reply['replies'] as List?, depth + 1, out, limit);
    }
  }

  /// Bluesky wraps a quoted post in `record`, or in `record.record` when
  /// the post also has media of its own.
  FeedItem? _quotedFrom(Map<String, dynamic>? embed) {
    if (embed == null) return null;

    var record = embed['record'] as Map<String, dynamic>?;
    // recordWithMedia nests the quote one level deeper.
    if (record != null && record['record'] is Map<String, dynamic>) {
      record = record['record'] as Map<String, dynamic>;
    }
    if (record == null) return null;

    // Blocked, deleted and not-found quotes come back as typed stubs.
    final type = record[r'$type'] as String? ?? '';
    if (type.contains('notFound') ||
        type.contains('blocked') ||
        type.contains('detached')) {
      return null;
    }

    final author = record['author'] as Map<String, dynamic>?;
    final value = record['value'] as Map<String, dynamic>?;
    if (author == null || value == null) return null;

    final handle = author['handle'] as String? ?? '';
    final uriParts = (record['uri'] as String? ?? '').split('/');
    final rkey = uriParts.isNotEmpty ? uriParts.last : '';

    return FeedItem(
      id: '${source.id}:quote:${record['cid'] ?? record['uri']}',
      sourceId: source.id,
      network: Network.bluesky,
      author: author['displayName'] as String? ?? handle,
      handle: '@$handle',
      avatarUrl: author['avatar'] as String?,
      text: value['text'] as String? ?? '',
      url: rkey.isNotEmpty
          ? 'https://bsky.app/profile/$handle/post/$rkey'
          : null,
      nativeId: record['uri'] as String?,
      createdAt:
          DateTime.tryParse(value['createdAt'] as String? ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
    );
  }

  static LinkCard? _linkCardFrom(Map<String, dynamic>? embed) {
    if (embed == null) return null;
    final external = (embed['external'] ??
            (embed['media'] as Map<String, dynamic>?)?['external'])
        as Map<String, dynamic>?;
    if (external == null) return null;

    final uri = external['uri'] as String?;
    if (uri == null) return null;

    return LinkCard(
      url: uri,
      title: external['title'] as String?,
      description: external['description'] as String?,
      imageUrl: external['thumb'] as String?,
    );
  }

  FeedItem _toItem(Map<String, dynamic> feedEntry) {
    final post = feedEntry['post'] as Map<String, dynamic>;
    final author = post['author'] as Map<String, dynamic>;
    final record = post['record'] as Map<String, dynamic>? ?? const {};

    String? repostedBy;
    final reason = feedEntry['reason'] as Map<String, dynamic>?;
    if (reason != null && (reason[r'$type'] as String? ?? '').contains('reasonRepost')) {
      final by = reason['by'] as Map<String, dynamic>?;
      repostedBy = by?['displayName'] as String? ?? by?['handle'] as String?;
    }

    final images = <MediaItem>[];
    final embed = post['embed'] as Map<String, dynamic>?;
    if (embed != null) {
      final list = (embed['images'] ??
          (embed['media'] as Map<String, dynamic>?)?['images']) as List?;
      for (final img in list ?? const []) {
        final image = img as Map<String, dynamic>;
        final thumb = image['thumb'] as String?;
        if (thumb != null) {
          images.add(MediaItem(url: thumb, alt: image['alt'] as String?));
        }
      }
    }

    // A quote with the quoted post missing reads as bare commentary, which
    // can mean the opposite of what the author intended.
    final quoted = _quotedFrom(embed);
    final linkCard = _linkCardFrom(embed);

    // Bluesky moderation happens through labels. Ignoring them means
    // bypassing the network's own content controls, so treat the adult
    // ones as a reason to hide the post until asked.
    final labels = (post['labels'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((l) => l['val'] as String?)
        .whereType<String>()
        .toList();
    final adultLabel = labels
        .where((l) => _adultLabels.contains(l))
        .firstOrNull;

    final handle = author['handle'] as String? ?? '';
    final uriParts = (post['uri'] as String? ?? '').split('/');
    final rkey = uriParts.isNotEmpty ? uriParts.last : '';

    return FeedItem(
      id: '${source.id}:${post['cid'] ?? post['uri']}',
      sourceId: source.id,
      network: Network.bluesky,
      author: author['displayName'] as String? ?? handle,
      handle: '@$handle',
      avatarUrl: author['avatar'] as String?,
      text: record['text'] as String? ?? '',
      url: rkey.isNotEmpty
          ? 'https://bsky.app/profile/$handle/post/$rkey'
          : null,
      nativeId: post['uri'] as String?,
      media: images,
      quoted: quoted,
      linkCard: linkCard,
      contentWarning: adultLabel == null ? null : _labelLabel(adultLabel),
      sensitive: adultLabel != null,
      repostedBy: repostedBy,
      likes: post['likeCount'] as int?,
      reposts: post['repostCount'] as int?,
      replies: post['replyCount'] as int?,
      context: source.displayName,
      createdAt:
          DateTime.tryParse(record['createdAt'] as String? ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
    );
  }
}
