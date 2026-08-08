import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

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

    // Why we gave up, kept so the final message says "rate limited" rather
    // than "private or quarantined" when those are very different problems.
    int? blockedAs;
    int? lastStatus;

    for (final host in _hosts) {
      final res = await httpClient.get(
        Uri.https(host, '/r/$subreddit/$sort.json',
            {'limit': '$limit', 'raw_json': '1'}),
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
      final viaRss = await _fetchViaRss(subreddit, sort, limit);
      if (viaRss != null) return viaRss;
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
            imageUrls: [if (image != null) image],
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
  Future<List<ThreadEntry>> fetchThread(FeedItem item, {int limit = 100}) async {
    final permalink = item.nativeId ?? item.url;
    if (permalink == null) return const [];

    final path = Uri.tryParse(permalink)?.path;
    if (path == null || path.isEmpty) return const [];

    for (final host in _hosts) {
      final res = await httpClient.get(
        Uri.https(host, '${path.replaceAll(RegExp(r'/$'), '')}.json',
            {'limit': '$limit', 'raw_json': '1', 'sort': 'top'}),
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
      _collectComments(
        (listings[1] as Map<String, dynamic>)['data'] as Map<String, dynamic>?,
        0,
        entries,
        limit,
      );
      return entries;
    }
    return const [];
  }

  /// Reddit nests replies as listings inside each comment, so walk down and
  /// flatten, carrying the depth for indentation.
  void _collectComments(
    Map<String, dynamic>? listing,
    int depth,
    List<ThreadEntry> out,
    int limit,
  ) {
    if (listing == null || out.length >= limit) return;

    for (final child in (listing['children'] as List? ?? const [])
        .cast<Map<String, dynamic>>()) {
      if (out.length >= limit) return;
      // "more" placeholders stand in for unloaded replies, not content.
      if (child['kind'] != 't1') continue;

      final data = child['data'] as Map<String, dynamic>?;
      if (data == null) continue;

      final bodyText = data['body'] as String? ?? '';
      if (bodyText.isEmpty) continue;

      out.add(ThreadEntry(
        depth: depth,
        item: FeedItem(
          id: '${source.id}:${data['name'] ?? data['id']}',
          sourceId: source.id,
          network: Network.reddit,
          author: 'u/${data['author'] ?? '[deleted]'}',
          text: htmlToPlainText(bodyText),
          url: data['permalink'] != null
              ? 'https://www.reddit.com${data['permalink']}'
              : null,
          likes: data['score'] as int?,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
              (((data['created_utc'] as num?)?.toDouble() ?? 0) * 1000).round(),
              isUtc: true),
        ),
      ));

      final replies = data['replies'];
      if (replies is Map<String, dynamic>) {
        _collectComments(
            replies['data'] as Map<String, dynamic>?, depth + 1, out, limit);
      }
    }
  }

  /// Returns null when the body isn't a Reddit listing — an HTML block page,
  /// or Reddit's `{"error": 403}` JSON. Callers treat that as blocked rather
  /// than letting a decode error escape to the user.
  List<FeedItem>? _tryParse(http.Response res) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      return null;
    }

    if (decoded is! Map<String, dynamic>) return null;
    final children = (decoded['data'] as Map<String, dynamic>?)?['children'];
    if (children is! List) return null;

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
      nativeId: post['permalink'] as String?,
      fullText: selftext.isNotEmpty ? selftext : null,
      sensitive: post['over_18'] as bool? ?? false,
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
