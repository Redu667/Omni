import 'dart:convert';

import '../models/feed_item.dart';
import '../models/network.dart';
import 'bluesky_session.dart';
import 'source_client.dart';

/// Bluesky (AT Protocol).
///
/// Three modes:
///  - `feed`: a custom feed generator or a list — the thing most Bluesky
///    users actually read, since the algorithm is the product there.
///  - `handle` only: a user's public author feed, no login required.
///  - `identifier` + `appPassword`: signs in and fetches the home timeline.
///
/// Credentials, when present, apply to all three: some feed generators only
/// answer authenticated requests.
class BlueskyClient extends SourceClient {
  BlueskyClient(super.source, super.httpClient, {BlueskySessions? sessions})
      : sessions = sessions ?? BlueskySessions();

  /// Shared across refreshes so one sign-in serves many fetches.
  final BlueskySessions sessions;

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
    final feedRef = source.params['feed'];

    final paging = {
      'limit': '$limit',
      if (cursor != null) 'cursor': cursor,
    };

    final signedIn = identifier != null &&
        identifier.isNotEmpty &&
        appPassword != null &&
        appPassword.isNotEmpty;

    // Sign in first when we can, so custom feeds that refuse anonymous
    // requests still work.
    var jwt = signedIn ? await _createSession(identifier, appPassword) : null;

    Future<({List feed, String? cursor})> run(String? jwt) async {
      final headers = jwt == null ? null : {'Authorization': 'Bearer $jwt'};
      final host = jwt == null ? _publicHost : _authHost;

      if (feedRef != null && feedRef.isNotEmpty) {
        final uri = await _resolveFeedUri(feedRef);
        final isList = uri.contains('/app.bsky.graph.list/');
        return _getFeed(
          Uri.https(
            host,
            isList
                ? '/xrpc/app.bsky.feed.getListFeed'
                : '/xrpc/app.bsky.feed.getFeed',
            {isList ? 'list' : 'feed': uri, ...paging},
          ),
          headers: headers,
          // A generator that wants a logged-in viewer answers 401/403, which
          // otherwise reads as "Bluesky is down".
          anonymousHint: jwt == null,
        );
      }
      if (jwt != null) {
        return _getFeed(
          Uri.https(_authHost, '/xrpc/app.bsky.feed.getTimeline', paging),
          headers: headers,
        );
      }
      final handle =
          (source.params['handle'] ?? '').replaceAll(RegExp(r'^@'), '');
      if (handle.isEmpty) {
        throw SourceFetchException(
            source.displayName, 'no handle, feed or credentials configured');
      }
      return _getFeed(
        Uri.https(_publicHost, '/xrpc/app.bsky.feed.getAuthorFeed',
            {'actor': handle, ...paging}),
      );
    }

    ({List feed, String? cursor}) result;
    try {
      result = await run(jwt);
    } on _Unauthorized {
      // A cached token outlived its welcome. Signing in again is the whole
      // point of keeping the password around, so do it once and retry
      // rather than reporting a failure the user can't act on.
      if (!signedIn) rethrow;
      sessions.invalidate(identifier);
      jwt = await _createSession(identifier, appPassword, forceRefresh: true);
      result = await run(jwt);
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

  Future<String> _createSession(String identifier, String appPassword,
      {bool forceRefresh = false}) async {
    try {
      return await sessions.accessToken(httpClient, identifier, appPassword,
          forceRefresh: forceRefresh);
    } on BlueskyAuthException catch (e) {
      throw SourceFetchException(source.displayName, e.toString());
    }
  }

  /// Turns whatever the user pasted into an `at://` URI.
  ///
  /// People copy the address bar, not the AT URI, so a bsky.app link has to
  /// work. The handle in that link has to be resolved to a DID, because the
  /// record lives under the DID, not the name.
  Future<String> _resolveFeedUri(String ref) async {
    final trimmed = ref.trim();
    if (trimmed.startsWith('at://')) return trimmed;

    final parsed = Uri.tryParse(trimmed);
    final segments = parsed?.pathSegments ?? const <String>[];
    // /profile/<actor>/feed/<rkey> or /profile/<actor>/lists/<rkey>
    final kindIndex = segments.length - 2;
    if (segments.length < 4 ||
        segments.first != 'profile' ||
        !(segments[kindIndex] == 'feed' || segments[kindIndex] == 'lists')) {
      throw SourceFetchException(
          source.displayName,
          'not a feed or list link — paste the address of a feed from '
          'bsky.app, or an at:// URI');
    }

    final collection = segments[kindIndex] == 'lists'
        ? 'app.bsky.graph.list'
        : 'app.bsky.feed.generator';
    return 'at://${await _resolveActor(segments[1])}/$collection/'
        '${segments.last}';
  }

  /// Handles resolve to DIDs; a DID is already what we need.
  Future<String> _resolveActor(String actor) async {
    if (actor.startsWith('did:')) return actor;

    final res = await httpClient.get(Uri.https(
        _publicHost, '/xrpc/com.atproto.identity.resolveHandle',
        {'handle': actor}));
    if (res.statusCode != 200) {
      throw SourceFetchException(
          source.displayName, 'no Bluesky account named $actor');
    }
    final did =
        (jsonDecode(res.body) as Map<String, dynamic>)['did'] as String?;
    if (did == null) {
      throw SourceFetchException(
          source.displayName, 'no Bluesky account named $actor');
    }
    return did;
  }

  Future<({List feed, String? cursor})> _getFeed(Uri uri,
      {Map<String, String>? headers, bool anonymousHint = false}) async {
    final res = await httpClient.get(uri, headers: headers);
    if (res.statusCode != 200) {
      if (anonymousHint &&
          (res.statusCode == 401 || res.statusCode == 403)) {
        throw SourceFetchException(
            source.displayName,
            'this feed only serves signed-in readers — add your handle and '
            'an app password to this source');
      }
      // Signed-in and rejected: the caller decides whether that's worth a
      // fresh sign-in or is simply a failure.
      if (res.statusCode == 401 && headers != null) throw const _Unauthorized();
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
  Future<PostThread> fetchThread(FeedItem item,
      {int limit = 100, String? sort}) async {
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

  /// A `app.bsky.embed.video#view`, which carries an HLS playlist rather
  /// than a plain file.
  static MediaItem? _videoFrom(Map<String, dynamic>? embed) {
    if (embed == null) return null;
    if (!(embed[r'$type'] as String? ?? '').contains('embed.video')) return null;

    final playlist = embed['playlist'] as String?;
    if (playlist == null) return null;

    return MediaItem(
      url: playlist,
      alt: embed['alt'] as String?,
      kind: MediaKind.video,
      thumbnailUrl: embed['thumbnail'] as String?,
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
      final media = embed['media'] as Map<String, dynamic>?;
      final list = (embed['images'] ?? media?['images']) as List?;
      for (final img in list ?? const []) {
        final image = img as Map<String, dynamic>;
        final thumb = image['thumb'] as String?;
        if (thumb != null) {
          images.add(MediaItem(url: thumb, alt: image['alt'] as String?));
        }
      }

      // Bluesky serves video as an HLS playlist, which ExoPlayer handles.
      // Either at the top level, or nested under recordWithMedia.
      final video = _videoFrom(embed) ?? _videoFrom(media);
      if (video != null) images.add(video);
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

/// A token Bluesky no longer accepts. Internal: it never escapes the client,
/// which either retries with a fresh token or reports a real failure.
class _Unauthorized implements Exception {
  const _Unauthorized();
}
