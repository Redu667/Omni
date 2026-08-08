import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/feed_repository.dart';
import 'package:omni/services/source_client.dart';

FeedSource src(Network network, Map<String, String> params, {String id = 's'}) =>
    FeedSource(id: id, network: network, displayName: 'T', params: params);

Map<String, dynamic> mastodonStatus(String id) => {
      'id': id,
      'created_at': '2026-08-05T12:00:00.000Z',
      'content': '<p>post $id</p>',
      'account': {'display_name': 'A', 'acct': 'a', 'username': 'a'},
      'media_attachments': [],
    };

void main() {
  group('Mastodon paging', () {
    test('pages with max_id taken from the oldest post', () async {
      final requests = <Uri>[];
      final client = MockClient((req) async {
        requests.add(req.url);
        // A full page keeps paging available.
        return http.Response(
            jsonEncode([for (var i = 0; i < 40; i++) mastodonStatus('$i')]),
            200);
      });

      final page = await SourceClient.forSource(
        src(Network.mastodon, {'instance': 'mastodon.social'}),
        client,
      ).fetchPage(limit: 40);

      expect(page.items, hasLength(40));
      expect(page.nextCursor, '39');
      expect(requests.single.queryParameters.containsKey('max_id'), isFalse);

      await SourceClient.forSource(
        src(Network.mastodon, {'instance': 'mastodon.social'}),
        client,
      ).fetchPage(limit: 40, cursor: page.nextCursor);

      expect(requests.last.queryParameters['max_id'], '39');
    });

    test('a short page means the end', () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode([mastodonStatus('1')]), 200));

      final page = await SourceClient.forSource(
        src(Network.mastodon, {'instance': 'mastodon.social'}),
        client,
      ).fetchPage(limit: 40);

      expect(page.hasMore, isFalse);
    });
  });

  group('Bluesky paging', () {
    test('passes the cursor back and reports the next one', () async {
      final requests = <Uri>[];
      final client = MockClient((req) async {
        requests.add(req.url);
        return http.Response(
            jsonEncode({
              'cursor': 'next-page-token',
              'feed': [
                {
                  'post': {
                    'uri': 'at://did/app.bsky.feed.post/1',
                    'cid': 'c1',
                    'author': {'handle': 'a.bsky.social', 'displayName': 'A'},
                    'record': {
                      'text': 'hi',
                      'createdAt': '2026-08-05T10:00:00.000Z',
                    },
                  },
                },
              ],
            }),
            200);
      });

      final page = await SourceClient.forSource(
        src(Network.bluesky, {'handle': 'a.bsky.social'}),
        client,
      ).fetchPage(limit: 40, cursor: 'previous-token');

      expect(requests.single.queryParameters['cursor'], 'previous-token');
      expect(page.nextCursor, 'next-page-token');
    });

    test('an empty page ends it, even with a cursor still offered', () async {
      // Bluesky keeps handing back a cursor past the end of a feed.
      final client = MockClient((_) async => http.Response(
          jsonEncode({'cursor': 'still-here', 'feed': []}), 200));

      final page = await SourceClient.forSource(
        src(Network.bluesky, {'handle': 'a.bsky.social'}),
        client,
      ).fetchPage();

      expect(page.hasMore, isFalse);
    });
  });

  group('Reddit paging', () {
    test('uses the after fullname', () async {
      final requests = <Uri>[];
      final client = MockClient((req) async {
        requests.add(req.url);
        return http.Response(
            jsonEncode({
              'data': {
                'after': 't3_next',
                'children': [
                  {
                    'data': {
                      'name': 't3_a',
                      'title': 'a post',
                      'author': 'x',
                      'subreddit': 'law',
                      'permalink': '/r/law/a/',
                      'created_utc': 1785924000,
                    },
                  },
                ],
              },
            }),
            200);
      });

      final page = await SourceClient.forSource(
        src(Network.reddit, {'subreddit': 'law'}),
        client,
      ).fetchPage(cursor: 't3_previous');

      expect(requests.first.queryParameters['after'], 't3_previous');
      expect(page.nextCursor, 't3_next');
    });

    test('the Atom fallback cannot page, so it never claims to', () async {
      final client = MockClient((req) async {
        if (req.url.path.endsWith('.rss')) {
          return http.Response('''
<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry><id>t3_a</id><title>x</title>
    <link href="https://reddit.com/r/law/a/"/>
    <updated>2026-08-06T12:00:00+00:00</updated>
    <author><name>/u/a</name></author>
  </entry>
</feed>''', 200);
        }
        return http.Response('<html>blocked</html>', 200);
      });

      final page = await SourceClient.forSource(
        src(Network.reddit, {'subreddit': 'law'}),
        client,
      ).fetchPage();

      expect(page.items, hasLength(1));
      expect(page.hasMore, isFalse);
    });

    test('asking a blocked subreddit for page two returns nothing', () async {
      final client = MockClient((_) async => http.Response('<html/>', 200));

      final page = await SourceClient.forSource(
        src(Network.reddit, {'subreddit': 'law'}),
        client,
      ).fetchPage(cursor: 't3_x');

      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });

  group('RSS paging', () {
    test('a feed is a fixed window, so there is never a second page',
        () async {
      final client = MockClient((_) async => http.Response('''
<?xml version="1.0"?>
<rss version="2.0"><channel><title>F</title>
  <item><title>One</title><link>https://e.com/1</link>
    <pubDate>Tue, 05 Aug 2026 08:00:00 +0000</pubDate></item>
</channel></rss>''', 200));

      final first = await SourceClient.forSource(
        src(Network.rss, {'url': 'https://e.com/feed'}),
        client,
      ).fetchPage();

      expect(first.items, hasLength(1));
      expect(first.hasMore, isFalse);
    });
  });

  group('repository', () {
    test('collects cursors per source and skips exhausted ones', () async {
      final requested = <String>[];
      final client = MockClient((req) async {
        requested.add(req.url.host);
        if (req.url.host.contains('mastodon')) {
          // Full page: still has more.
          return http.Response(
              jsonEncode([for (var i = 0; i < 5; i++) mastodonStatus('m$i')]),
              200);
        }
        // Short RSS feed: done after one page.
        return http.Response('''
<?xml version="1.0"?>
<rss version="2.0"><channel><title>F</title>
  <item><title>One</title><link>https://e.com/1</link>
    <pubDate>Tue, 05 Aug 2026 08:00:00 +0000</pubDate></item>
</channel></rss>''', 200);
      });

      final repo = FeedRepository(httpClient: client);
      final sources = [
        src(Network.mastodon, {'instance': 'mastodon.social'}, id: 'm'),
        src(Network.rss, {'url': 'https://feeds.example.com/f'}, id: 'r'),
      ];

      final first = await repo.fetchAll(sources, limitPerSource: 5);
      expect(first.items, hasLength(6));
      expect(first.cursors.keys, ['m']);
      expect(first.hasMore, isTrue);

      requested.clear();
      final second =
          await repo.fetchAll(sources, limitPerSource: 5, cursors: first.cursors);

      // Only the source with a cursor is asked again.
      expect(requested.every((h) => h.contains('mastodon')), isTrue);
      expect(second.items, hasLength(5));
    });

    test('no cursors at all means the feed is complete', () async {
      final client = MockClient((_) async => http.Response('''
<?xml version="1.0"?>
<rss version="2.0"><channel><title>F</title>
  <item><title>One</title><link>https://e.com/1</link>
    <pubDate>Tue, 05 Aug 2026 08:00:00 +0000</pubDate></item>
</channel></rss>''', 200));

      final result = await FeedRepository(httpClient: client)
          .fetchAll([src(Network.rss, {'url': 'https://e.com/f'})]);

      expect(result.hasMore, isFalse);
    });
  });
}
