import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/feed_item.dart';
import '../models/network.dart';
import '../util/text.dart';
import 'reddit_auth.dart';
import 'source_client.dart';

/// Reddit via the public JSON listing API (no account needed).
///
/// `subreddit` may combine several with '+', e.g. "flutter+androiddev".
class RedditClient extends SourceClient {
  RedditClient(super.source, super.httpClient, {this.auth});

  /// When configured, requests go to oauth.reddit.com with a bearer token,
  /// which is not subject to the blocking anonymous callers get.
  final RedditAuth? auth;

  /// Reddit turns away clients that don't look like a browser, so present as
  /// one. old.reddit.com serves the same JSON and is markedly less
  /// aggressive about blocking, which is why it's tried as a fallback.
  static const _hosts = ['www.reddit.com', 'old.reddit.com'];
  static const _oauthHost = 'oauth.reddit.com';

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/124.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  /// Adds the bearer token when one is available. Returns null when Reddit
  /// isn't configured, so callers know to use the anonymous hosts.
  Future<Map<String, String>?> _authHeaders() async {
    if (auth == null) return null;
    try {
      final token = await auth!.token();
      if (token == null) return null;
      return {
        ..._headers,
        'Authorization': 'Bearer $token',
        'User-Agent': RedditAuth.userAgent,
      };
    } on RedditAuthException {
      // A bad client id shouldn't break the source; fall back to anonymous
      // and let the usual blocked-path handling take over.
      return null;
    }
  }

  @override
  Future<SourcePage> fetchPage({int limit = 40, String? cursor}) async {
    final subreddit = source.params['subreddit']!.replaceAll(RegExp(r'^/?r/'), '');
    final sort = source.params['sort'] ?? 'hot';

    // "Top of all time" and "top of today" are entirely different feeds, and
    // Reddit defaults to the day. Only top and controversial take a window.
    final window = source.params['t'];
    final windowed =
        (sort == 'top' || sort == 'controversial') && window != null;

    // Authenticated first: it isn't blocked, and it carries the full
    // listing rather than the Atom feed's reduced fields.
    final authHeaders = await _authHeaders();
    if (authHeaders != null) {
      final res = await httpClient.get(
        Uri.https(_oauthHost, '/r/$subreddit/$sort', {
          'limit': '$limit',
          'raw_json': '1',
          if (windowed) 't': window,
          if (cursor != null) 'after': cursor,
        }),
        headers: authHeaders,
      );
      if (res.statusCode == 200) {
        final parsed = _tryParse(res);
        if (parsed != null) return parsed;
      }
      if (res.statusCode == 401) auth?.invalidate();
      // Anything else falls through to the anonymous path below.
    }

    // Why we gave up, kept so the final message says "rate limited" rather
    // than "private or quarantined" when those are very different problems.
    int? blockedAs;
    int? lastStatus;

    for (final host in _hosts) {
      final res = await httpClient.get(
        Uri.https(host, '/r/$subreddit/$sort.json', {
          'limit': '$limit',
          'raw_json': '1',
          if (windowed) 't': window,
          if (cursor != null) 'after': cursor,
        }),
        headers: _headers,
      );
      lastStatus = res.statusCode;

      if (res.statusCode == 200) {
        final parsed = _tryParse(res);
        if (parsed != null) return parsed;
        // Reddit serves its block and challenge pages as HTML with a 200,
        // so a body that isn't a listing means blocked, not empty.
        blockedAs = 403;
        continue;
      }

      if (res.statusCode == 403 || res.statusCode == 429) {
        blockedAs = res.statusCode;
        continue;
      }
      // Anything else means the same thing on every host — stop asking.
      break;
    }
    final blocked = blockedAs != null;

    // Reddit blocks the JSON listings for anything that isn't a real browser
    // session, including on plainly public subreddits. The Atom feeds are
    // still served openly, so fall back to those rather than failing —
    // fewer fields, but a working feed.
    if (blocked) {
      // Atom has no paging, so a second page never has anything to add.
      if (cursor != null) return const SourcePage.last([]);
      final viaRss = await _fetchViaRss(subreddit, sort, limit);
      if (viaRss != null) return SourcePage.last(viaRss);
    }

    throw SourceFetchException(
        source.displayName, _explain(blockedAs ?? lastStatus ?? 0, subreddit));
  }

  /// Reddit uses the same status code for several very different problems,
  /// so say which one it likely is rather than echoing a bare number.
  static String _explain(int status, String subreddit) => switch (status) {
        403 =>
          'Reddit refused the request for r/$subreddit (403), and its feed did '
              'not answer either. That subreddit may be private, quarantined or '
              'banned — otherwise Reddit is blocking anonymous access from your '
              'network right now.',
        404 => 'No subreddit called r/$subreddit.',
        429 =>
          'Reddit is rate limiting right now, and its feed did not answer '
              'either — try again in a minute.',
        _ => 'HTTP $status from Reddit.',
      };

  /// Parses `/r/<sub>/<sort>.rss`, which Reddit serves as Atom. Scores and
  /// comment counts aren't in the feed, so those come back null.
  Future<List<FeedItem>?> _fetchViaRss(
      String subreddit, String sort, int limit) async {
    final res = await httpClient.get(
      Uri.https('www.reddit.com', '/r/$subreddit/$sort.rss', {'limit': '$limit'}),
      headers: {
        ..._headers,
        'Accept': 'application/atom+xml, application/xml, text/xml',
      },
    );
    if (res.statusCode != 200) return null;

    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(utf8.decode(res.bodyBytes));
    } on XmlException {
      return null;
    }

    // A block page can still parse as XML, so an absence of entries means
    // this route failed too rather than "the subreddit is empty".
    final entries = doc.findAllElements('entry').take(limit);
    if (entries.isEmpty) return null;

    return [
      for (final entry in entries)
        () {
          String text(String tag) =>
              entry.getElement(tag)?.innerText.trim() ?? '';

          final link = entry.getElement('link')?.getAttribute('href');
          final author = entry
                  .getElement('author')
                  ?.getElement('name')
                  ?.innerText
                  .trim() ??
              '[deleted]';
          // Reddit puts a real thumbnail here for link posts — the main
          // reason a link-heavy subreddit has any imagery at all.
          final thumbnail = entry
              .findElements('media:thumbnail')
              .firstOrNull
              ?.getAttribute('url');

          final contentHtml = entry.getElement('content')?.innerText ?? '';
          final embedded =
              RegExp('''<img[^>]+src=["']([^"']+)["']''', caseSensitive: false)
                  .firstMatch(contentHtml)
                  ?.group(1);

          // Escaped HTML leaves `&amp;` in the query string, which 404s
          // unless undone. Reddit also uses placeholder values like "self"
          // and "default" where a post simply has no image.
          final raw = thumbnail ?? embedded;
          final image = (raw == null || !raw.startsWith('http'))
              ? null
              : unescapeHtml(raw);

          return FeedItem(
            id: '${source.id}:${text('id').isNotEmpty ? text('id') : link}',
            sourceId: source.id,
            network: Network.reddit,
            author: author.startsWith('/u/') ? author.substring(1) : author,
            title: htmlToPlainText(text('title')),
            url: link,
            nativeId: link,
            media: [if (image != null) MediaItem(url: image)],
            context: 'r/$subreddit',
            createdAt: DateTime.tryParse(
                        text('updated').isNotEmpty
                            ? text('updated')
                            : text('published'))
                    ?.toUtc() ??
                DateTime.now().toUtc(),
          );
        }(),
    ];
  }

  @override
  bool get supportsAuthorFeed => true;

  @override
  Future<List<FeedItem>> fetchAuthorPosts(FeedItem item, {int limit = 40}) async {
    final user = item.author.replaceFirst(RegExp(r'^/?u/'), '');
    if (user.isEmpty || user.startsWith('[')) return const [];

    for (final host in _hosts) {
      final res = await httpClient.get(
        Uri.https(host, '/user/$user/submitted.json',
            {'limit': '$limit', 'raw_json': '1'}),
        headers: _headers,
      );
      if (res.statusCode != 200) continue;
      final parsed = _tryParse(res);
      if (parsed != null) return parsed.items;
    }
    throw SourceFetchException(
        source.displayName, 'Reddit would not serve u/$user right now.');
  }

  @override
  Map<String, String> get commentSorts => const {
        'confidence': 'Best',
        'top': 'Top',
        'new': 'New',
        'old': 'Old',
        'controversial': 'Controversial',
        'qa': 'Q&A',
      };

  @override
  Future<PostThread> fetchThread(FeedItem item,
      {int limit = 100, String? sort}) async {
    final permalink = item.nativeId ?? item.url;
    if (permalink == null) return PostThread.empty;

    final path = Uri.tryParse(permalink)?.path;
    if (path == null || path.isEmpty) return PostThread.empty;

    for (final host in _hosts) {
      final res = await httpClient.get(
        Uri.https(host, '${path.replaceAll(RegExp(r'/$'), '')}.json', {
          'limit': '$limit',
          'raw_json': '1',
          'sort': commentSorts.containsKey(sort) ? sort! : 'confidence',
        }),
        headers: _headers,
      );
      if (res.statusCode != 200) continue;

      // The response is [post listing, comment listing] — unless Reddit
      // served a block page, which decodes to something else entirely.
      final Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
      } on FormatException {
        continue;
      }
      if (decoded is! List || decoded.length < 2) continue;
      final listings = decoded;

      final entries = <ThreadEntry>[];
      final root = _collectComments(
        (listings[1] as Map<String, dynamic>)['data'] as Map<String, dynamic>?,
        0,
        entries,
        limit,
      );
      // A Reddit post is always the root of its own thread.
      return PostThread(replies: entries, more: root);
    }
    return PostThread.empty;
  }

  /// Reddit nests replies as listings inside each comment, so walk down and
  /// flatten, carrying the depth for indentation.
  ///
  /// Returns this listing's own `more` stub — the comments Reddit truncated
  /// at this level — so the caller can offer to load them.
  MoreReplies? _collectComments(
    Map<String, dynamic>? listing,
    int depth,
    List<ThreadEntry> out,
    int limit,
  ) {
    if (listing == null || out.length >= limit) return null;

    MoreReplies? truncated;
    for (final child in (listing['children'] as List? ?? const [])
        .cast<Map<String, dynamic>>()) {
      if (out.length >= limit) return truncated;

      // "more" placeholders stand in for unloaded replies, not content.
      if (child['kind'] == 'more') {
        truncated = _moreFrom(child['data'] as Map<String, dynamic>?, depth);
        continue;
      }
      if (child['kind'] != 't1') continue;

      final data = child['data'] as Map<String, dynamic>?;
      if (data == null) continue;

      final bodyText = data['body'] as String? ?? '';
      if (bodyText.isEmpty) continue;

      final index = out.length;
      out.add(ThreadEntry(
        depth: depth,
        item: _commentItem(data),
      ));

      final replies = data['replies'];
      if (replies is Map<String, dynamic>) {
        final nested = _collectComments(
            replies['data'] as Map<String, dynamic>?, depth + 1, out, limit);
        // Hangs off the comment whose replies were cut short, so the button
        // appears where the missing replies belong.
        if (nested != null) out[index] = out[index].withMore(nested);
      }
    }
    return truncated;
  }

  static MoreReplies? _moreFrom(Map<String, dynamic>? data, int depth) {
    if (data == null) return null;
    final ids = (data['children'] as List? ?? const [])
        .map((c) => c.toString())
        .where((c) => c.isNotEmpty)
        .toList();
    if (ids.isEmpty) return null;
    return MoreReplies(
      count: (data['count'] as num?)?.toInt() ?? ids.length,
      ids: ids,
      depth: depth,
    );
  }

  FeedItem _commentItem(Map<String, dynamic> data) => FeedItem(
        id: '${source.id}:${data['name'] ?? data['id']}',
        sourceId: source.id,
        network: Network.reddit,
        author: 'u/${data['author'] ?? '[deleted]'}',
        text: htmlToPlainText(data['body'] as String? ?? ''),
        url: data['permalink'] != null
            ? 'https://www.reddit.com${data['permalink']}'
            : null,
        likes: data['score'] as int?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (((data['created_utc'] as num?)?.toDouble() ?? 0) * 1000).round(),
            isUtc: true),
      );

  @override
  Future<List<ThreadEntry>> fetchMoreReplies(FeedItem item, MoreReplies more,
      {String? sort}) async {
    // The post's fullname is what morechildren keys on, and the permalink is
    // the only place we reliably have its id — nativeId is a path from the
    // JSON API and an absolute URL from the Atom fallback, so parse both.
    final segments = Uri.parse(item.nativeId ?? item.url ?? '').pathSegments;
    final at = segments.indexOf('comments');
    final postId =
        at >= 0 ? segments.elementAtOrNull(at + 1) : null;
    if (postId == null || postId.isEmpty || more.isEmpty) return const [];
    final linkId = 't3_$postId';

    // Reddit caps a morechildren request at 100 ids; the rest stays behind
    // the next button.
    final batch = more.ids.take(100).join(',');

    for (final host in _hosts) {
      final res = await httpClient.get(
        Uri.https(host, '/api/morechildren.json', {
          'api_type': 'json',
          'link_id': linkId,
          'children': batch,
          'raw_json': '1',
          'sort': commentSorts.containsKey(sort) ? sort! : 'confidence',
        }),
        headers: _headers,
      );
      if (res.statusCode != 200) continue;

      final Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
      } on FormatException {
        continue;
      }
      if (decoded is! Map<String, dynamic>) continue;

      final things = ((decoded['json'] as Map<String, dynamic>?)?['data']
          as Map<String, dynamic>?)?['things'] as List?;
      if (things == null) continue;

      return _flatten(things.cast<Map<String, dynamic>>(), more.depth);
    }
    return const [];
  }

  /// `morechildren` answers with a flat list rather than a tree, so depth has
  /// to be rebuilt from each comment's parent. Reddit sends parents before
  /// their children, which is what makes one pass enough.
  List<ThreadEntry> _flatten(List<Map<String, dynamic>> things, int baseDepth) {
    final depths = <String, int>{};
    final out = <ThreadEntry>[];

    for (final thing in things) {
      final data = thing['data'] as Map<String, dynamic>?;
      if (data == null) continue;

      final parent = data['parent_id'] as String?;
      final depth = parent != null && depths.containsKey(parent)
          ? depths[parent]! + 1
          : baseDepth;

      if (thing['kind'] == 'more') {
        // A nested truncation: attach it to the parent we already emitted.
        final more = _moreFrom(data, depth);
        final index =
            out.lastIndexWhere((e) => e.item.id == '${source.id}:$parent');
        if (more != null && index >= 0) out[index] = out[index].withMore(more);
        continue;
      }
      if (thing['kind'] != 't1') continue;

      final name = data['name'] as String?;
      if (name != null) depths[name] = depth;

      if ((data['body'] as String? ?? '').isEmpty) continue;
      out.add(ThreadEntry(depth: depth, item: _commentItem(data)));
    }
    return out;
  }

  /// Returns null when the body isn't a Reddit listing — an HTML block page,
  /// or Reddit's `{"error": 403}` JSON. Callers treat that as blocked rather
  /// than letting a decode error escape to the user.
  SourcePage? _tryParse(http.Response res) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      return null;
    }

    if (decoded is! Map<String, dynamic>) return null;
    final data = decoded['data'] as Map<String, dynamic>?;
    final children = data?['children'];
    if (children is! List) return null;

    return SourcePage(
      items: children
          .map((c) => _toItem((c as Map<String, dynamic>)['data']
              as Map<String, dynamic>))
          .toList(growable: false),
      // Reddit pages by the fullname of the last item it gave you.
      nextCursor: children.isEmpty ? null : data?['after'] as String?,
    );
  }

  FeedItem _toItem(Map<String, dynamic> post) {
    // A crosspost carries its content on the original, not the wrapper,
    // so an unresolved one renders as an empty post.
    final crosspost = (post['crosspost_parent_list'] as List?)
        ?.cast<Map<String, dynamic>>()
        .firstOrNull;
    final content = crosspost ?? post;

    final images = _imagesFrom(content);
    final selftext = content['selftext'] as String? ?? '';
    final createdUtc = (post['created_utc'] as num?)?.toDouble() ?? 0;

    return FeedItem(
      id: '${source.id}:${post['name'] ?? post['id']}',
      sourceId: source.id,
      network: Network.reddit,
      author: 'u/${post['author'] ?? '[deleted]'}',
      title: htmlToPlainText(post['title'] as String? ?? ''),
      text: selftext.length > 500 ? '${selftext.substring(0, 500)}…' : selftext,
      url: 'https://www.reddit.com${post['permalink'] ?? ''}',
      nativeId: post['permalink'] as String?,
      fullText: selftext.isNotEmpty ? selftext : null,
      sensitive: post['over_18'] as bool? ?? false,
      flair: (post['link_flair_text'] as String?)?.trim().isNotEmpty == true
          ? (post['link_flair_text'] as String).trim()
          : null,
      linkCard: _linkCardFrom(content),
      media: images,
      likes: post['ups'] as int?,
      replies: post['num_comments'] as int?,
      repostedBy: crosspost == null
          ? null
          : 'crossposted from r/${crosspost['subreddit']}',
      context: 'r/${post['subreddit'] ?? source.params['subreddit']}',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (createdUtc * 1000).round(),
          isUtc: true),
    );
  }

  /// Gallery posts hold their images in media_metadata rather than preview,
  /// so without this only one of several shows.
  List<MediaItem> _imagesFrom(Map<String, dynamic> post) {
    final images = <MediaItem>[];

    final galleryItems = (post['gallery_data']
            as Map<String, dynamic>?)?['items'] as List?;
    final metadata = post['media_metadata'] as Map<String, dynamic>?;
    if (galleryItems != null && metadata != null) {
      for (final entry in galleryItems.cast<Map<String, dynamic>>()) {
        final meta = metadata[entry['media_id']] as Map<String, dynamic>?;
        final url = (meta?['s'] as Map<String, dynamic>?)?['u'] as String?;
        if (url != null) {
          images.add(MediaItem(
            url: unescapeHtml(url),
            alt: (entry['caption'] as String?)?.trim().isNotEmpty == true
                ? entry['caption'] as String
                : null,
          ));
        }
      }
      if (images.isNotEmpty) return images;
    }

    final preview = post['preview'] as Map<String, dynamic>?;
    final previewImages = preview?['images'] as List?;
    if (previewImages != null && previewImages.isNotEmpty) {
      final url = ((previewImages.first as Map<String, dynamic>)['source']
          as Map<String, dynamic>?)?['url'] as String?;
      if (url != null) images.add(MediaItem(url: unescapeHtml(url)));
    } else {
      final direct = post['url_overridden_by_dest'] as String? ?? '';
      if (RegExp(r'\.(png|jpe?g|gif|webp)$').hasMatch(direct)) {
        images.add(MediaItem(url: direct));
      }
    }
    return images;
  }

  /// A link post points somewhere; showing where is the point of it.
  static LinkCard? _linkCardFrom(Map<String, dynamic> post) {
    final dest = post['url_overridden_by_dest'] as String?;
    if (dest == null || !dest.startsWith('http')) return null;
    // Reddit-hosted media isn't an outbound link worth carding.
    if (RegExp(r'(redd\.it|reddit\.com)').hasMatch(dest)) return null;
    if (RegExp(r'\.(png|jpe?g|gif|webp)$').hasMatch(dest)) return null;

    return LinkCard(url: dest, title: Uri.tryParse(dest)?.host);
  }

}
