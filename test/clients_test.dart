import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/source_client.dart';

FeedSource source(Network network, Map<String, String> params) => FeedSource(
      id: 'test',
      network: network,
      displayName: 'Test source',
      params: params,
    );

void main() {
  group('MastodonClient', () {
    test('parses public timeline statuses including boosts', () async {
      final statuses = [
        {
          'id': '1',
          'created_at': '2026-08-05T12:00:00.000Z',
          'content': '<p>Hello <b>fediverse</b></p>',
          'url': 'https://mastodon.social/@alice/1',
          'favourites_count': 5,
          'reblogs_count': 2,
          'replies_count': 1,
          'account': {
            'display_name': 'Alice',
            'acct': 'alice',
            'username': 'alice',
            'avatar': 'https://cdn/avatar.png',
          },
          'media_attachments': [
            {'type': 'image', 'preview_url': 'https://cdn/img.png'},
            {'type': 'video', 'preview_url': 'https://cdn/vid.png'},
          ],
        },
        {
          'id': '2',
          'created_at': '2026-08-05T13:00:00.000Z',
          'content': '',
          'account': {
            'display_name': 'Boosting Bob',
            'acct': 'bob',
            'username': 'bob',
            'avatar': null,
          },
          'media_attachments': [],
          'reblog': {
            'id': '3',
            'created_at': '2026-08-05T11:00:00.000Z',
            'content': '<p>original post</p>',
            'url': 'https://example.social/@carol/3',
            'account': {
              'display_name': 'Carol',
              'acct': 'carol@example.social',
              'username': 'carol',
              'avatar': null,
            },
            'media_attachments': [],
          },
        },
      ];

      late Uri requested;
      final client = MockClient((req) async {
        requested = req.url;
        return http.Response(jsonEncode(statuses), 200,
            headers: {'content-type': 'application/json'});
      });

      final items = await SourceClient.forSource(
        source(Network.mastodon, {'instance': 'mastodon.social'}),
        client,
      ).fetchLatest();

      expect(requested.path, '/api/v1/timelines/public');
      expect(items, hasLength(2));
      expect(items[0].author, 'Alice');
      expect(items[0].handle, '@alice');
      expect(items[0].text, 'Hello fediverse');
      expect(items[0].imageUrls, ['https://cdn/img.png']);
      expect(items[0].likes, 5);
      expect(items[1].repostedBy, 'Boosting Bob');
      expect(items[1].author, 'Carol');
      expect(items[1].text, 'original post');
    });

    test('uses home timeline with token', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response('[]', 200);
      });

      await SourceClient.forSource(
        source(Network.mastodon,
            {'instance': 'mastodon.social', 'accessToken': 'tok123'}),
        client,
      ).fetchLatest();

      expect(captured.url.path, '/api/v1/timelines/home');
      expect(captured.headers['Authorization'], 'Bearer tok123');
    });
  });

  group('BlueskyClient', () {
    test('parses a public author feed with repost reason', () async {
      final feed = {
        'feed': [
          {
            'post': {
              'uri': 'at://did:plc:abc/app.bsky.feed.post/3xyz',
              'cid': 'cid1',
              'author': {
                'handle': 'alice.bsky.social',
                'displayName': 'Alice',
                'avatar': 'https://cdn/a.jpg',
              },
              'record': {
                'text': 'hello sky',
                'createdAt': '2026-08-05T10:00:00.000Z',
              },
              'embed': {
                'images': [
                  {'thumb': 'https://cdn/thumb.jpg', 'fullsize': 'https://cdn/full.jpg'},
                ],
              },
              'likeCount': 10,
              'repostCount': 3,
              'replyCount': 2,
            },
            'reason': {
              r'$type': 'app.bsky.feed.defs#reasonRepost',
              'by': {'handle': 'bob.bsky.social', 'displayName': 'Bob'},
            },
          },
        ],
      };

      late Uri requested;
      final client = MockClient((req) async {
        requested = req.url;
        return http.Response(jsonEncode(feed), 200);
      });

      final items = await SourceClient.forSource(
        source(Network.bluesky, {'handle': '@alice.bsky.social'}),
        client,
      ).fetchLatest();

      expect(requested.host, 'public.api.bsky.app');
      expect(requested.queryParameters['actor'], 'alice.bsky.social');
      expect(items, hasLength(1));
      expect(items[0].author, 'Alice');
      expect(items[0].url,
          'https://bsky.app/profile/alice.bsky.social/post/3xyz');
      expect(items[0].imageUrls, ['https://cdn/thumb.jpg']);
      expect(items[0].repostedBy, 'Bob');
      expect(items[0].likes, 10);
    });
  });

  group('RedditClient', () {
    test('parses a listing', () async {
      final listing = {
        'data': {
          'children': [
            {
              'data': {
                'name': 't3_abc',
                'title': 'A &amp; B',
                'selftext': 'body text',
                'author': 'someone',
                'subreddit': 'flutter',
                'permalink': '/r/flutter/comments/abc/a_b/',
                'created_utc': 1754400000,
                'ups': 42,
                'num_comments': 7,
                'preview': {
                  'images': [
                    {
                      'source': {'url': 'https://preview.redd.it/x.png'},
                    },
                  ],
                },
              },
            },
          ],
        },
      };

      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode(listing), 200);
      });

      final items = await SourceClient.forSource(
        source(Network.reddit, {'subreddit': 'flutter'}),
        client,
      ).fetchLatest();

      expect(captured.url.path, '/r/flutter/hot.json');
      expect(captured.headers['User-Agent'], isNotEmpty);
      expect(items, hasLength(1));
      expect(items[0].title, 'A & B');
      expect(items[0].author, 'u/someone');
      expect(items[0].context, 'r/flutter');
      expect(items[0].url, 'https://www.reddit.com/r/flutter/comments/abc/a_b/');
      expect(items[0].imageUrls, ['https://preview.redd.it/x.png']);
      expect(items[0].likes, 42);
      expect(items[0].createdAt,
          DateTime.fromMillisecondsSinceEpoch(1754400000 * 1000, isUtc: true));
    });
  });

  group('RssClient', () {
    test('parses RSS 2.0', () async {
      const rss = '''
<?xml version="1.0"?>
<rss version="2.0">
  <channel>
    <title>Example Blog</title>
    <item>
      <title>First &amp; foremost</title>
      <link>https://example.com/1</link>
      <guid>https://example.com/1</guid>
      <description>&lt;p&gt;Some &lt;b&gt;rich&lt;/b&gt; text&lt;/p&gt;</description>
      <pubDate>Tue, 05 Aug 2026 08:00:00 +0000</pubDate>
      <enclosure url="https://example.com/img.jpg" type="image/jpeg"/>
    </item>
  </channel>
</rss>''';

      final client = MockClient((_) async => http.Response(rss, 200));

      final items = await SourceClient.forSource(
        source(Network.rss, {'url': 'https://example.com/feed.xml'}),
        client,
      ).fetchLatest();

      expect(items, hasLength(1));
      expect(items[0].title, 'First & foremost');
      expect(items[0].text, 'Some rich text');
      expect(items[0].url, 'https://example.com/1');
      expect(items[0].context, 'Example Blog');
      expect(items[0].imageUrls, ['https://example.com/img.jpg']);
      expect(items[0].createdAt, DateTime.utc(2026, 8, 5, 8));
    });

    test('parses Atom', () async {
      const atom = '''
<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Feed</title>
  <entry>
    <id>tag:example.com,2026:1</id>
    <title>Atom entry</title>
    <link rel="alternate" href="https://example.com/atom-1"/>
    <summary>plain summary</summary>
    <published>2026-08-04T09:30:00Z</published>
    <author><name>Writer</name></author>
  </entry>
</feed>''';

      final client = MockClient((_) async => http.Response(atom, 200));

      final items = await SourceClient.forSource(
        source(Network.rss, {'url': 'https://example.com/atom.xml'}),
        client,
      ).fetchLatest();

      expect(items, hasLength(1));
      expect(items[0].title, 'Atom entry');
      expect(items[0].author, 'Writer');
      expect(items[0].url, 'https://example.com/atom-1');
      expect(items[0].createdAt, DateTime.utc(2026, 8, 4, 9, 30));
    });

    test('throws a clear error on non-feed content', () async {
      final client =
          MockClient((_) async => http.Response('<html></html>', 200));

      expect(
        SourceClient.forSource(
          source(Network.rss, {'url': 'https://example.com/'}),
          client,
        ).fetchLatest(),
        throwsA(isA<SourceFetchException>()),
      );
    });
  });

  group('TwitterClient', () {
    test('parses recent search with includes', () async {
      final body = {
        'data': [
          {
            'id': '111',
            'author_id': 'u1',
            'text': 'tweet text',
            'created_at': '2026-08-05T15:00:00.000Z',
            'public_metrics': {
              'like_count': 9,
              'retweet_count': 4,
              'reply_count': 1,
            },
            'attachments': {
              'media_keys': ['m1'],
            },
          },
        ],
        'includes': {
          'users': [
            {
              'id': 'u1',
              'name': 'Dev Person',
              'username': 'devperson',
              'profile_image_url': 'https://pbs/x.jpg',
            },
          ],
          'media': [
            {'media_key': 'm1', 'type': 'photo', 'url': 'https://pbs/m.jpg'},
          ],
        },
      };

      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode(body), 200);
      });

      final items = await SourceClient.forSource(
        source(Network.twitter,
            {'bearerToken': 'tok', 'usernames': 'devperson'}),
        client,
      ).fetchLatest();

      expect(captured.headers['Authorization'], 'Bearer tok');
      expect(captured.url.queryParameters['query'], contains('from:devperson'));
      expect(items, hasLength(1));
      expect(items[0].author, 'Dev Person');
      expect(items[0].handle, '@devperson');
      expect(items[0].url, 'https://x.com/devperson/status/111');
      expect(items[0].imageUrls, ['https://pbs/m.jpg']);
      expect(items[0].reposts, 4);
    });

    test('explains paid-plan failures', () async {
      final client = MockClient((_) async => http.Response('{}', 403));

      expect(
        SourceClient.forSource(
          source(Network.twitter, {'bearerToken': 'bad', 'usernames': 'x'}),
          client,
        ).fetchLatest(),
        throwsA(predicate((e) =>
            e is SourceFetchException && e.message.contains('paid plan'))),
      );
    });
  });
}
