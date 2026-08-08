import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_item.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/source_client.dart';

FeedSource src(Network network, Map<String, String> params) => FeedSource(
      id: 's',
      network: network,
      displayName: 'Test',
      params: params,
    );

FeedItem itemWith({required Network network, String? nativeId, String? url}) =>
    FeedItem(
      id: 's:1',
      sourceId: 's',
      network: network,
      author: 'someone',
      nativeId: nativeId,
      url: url,
      createdAt: DateTime.utc(2026, 8, 1),
    );

void main() {
  group('Reddit comments', () {
    Map<String, dynamic> comment(String id, String body, int score,
            {List<Map<String, dynamic>>? replies}) =>
        {
          'kind': 't1',
          'data': {
            'name': id,
            'author': 'user_$id',
            'body': body,
            'score': score,
            'created_utc': 1785924000,
            'permalink': '/r/law/comments/x/_/$id/',
            if (replies != null)
              'replies': {
                'data': {'children': replies},
              },
          },
        };

    test('flattens the comment tree with depth', () async {
      final payload = [
        {'data': {}},
        {
          'data': {
            'children': [
              comment('c1', 'top level', 10, replies: [
                comment('c2', 'a reply', 5, replies: [
                  comment('c3', 'nested deeper', 2),
                ]),
              ]),
              comment('c4', 'another top level', 8),
            ],
          },
        },
      ];

      final client = MockClient((_) async => http.Response(jsonEncode(payload), 200));
      final thread = await SourceClient.forSource(
        src(Network.reddit, {'subreddit': 'law'}),
        client,
      ).fetchThread(itemWith(
          network: Network.reddit,
          nativeId: '/r/law/comments/x/title/'));
      final entries = thread.replies;

      expect(entries.map((e) => e.item.text),
          ['top level', 'a reply', 'nested deeper', 'another top level']);
      expect(entries.map((e) => e.depth), [0, 1, 2, 0]);
      expect(entries.first.item.author, 'u/user_c1');
      expect(entries.first.item.likes, 10);
    });

    test('skips "more comments" placeholders', () async {
      final payload = [
        {'data': {}},
        {
          'data': {
            'children': [
              comment('c1', 'real comment', 1),
              {'kind': 'more', 'data': {'count': 47}},
            ],
          },
        },
      ];

      final client = MockClient((_) async => http.Response(jsonEncode(payload), 200));
      final thread = await SourceClient.forSource(
        src(Network.reddit, {'subreddit': 'law'}),
        client,
      ).fetchThread(itemWith(
          network: Network.reddit, nativeId: '/r/law/comments/x/t/'));

      expect(thread.replies, hasLength(1));
    });
  });

  group('Mastodon context', () {
    test('derives depth from the reply chain', () async {
      Map<String, dynamic> status(String id, String? parent, String body) => {
            'id': id,
            'in_reply_to_id': parent,
            'created_at': '2026-08-01T10:00:00.000Z',
            'content': '<p>$body</p>',
            'account': {'display_name': 'A', 'acct': 'a', 'username': 'a'},
            'media_attachments': [],
          };

      final payload = {
        'ancestors': [],
        'descendants': [
          status('2', '1', 'direct reply'),
          status('3', '2', 'reply to the reply'),
          status('4', '1', 'another direct reply'),
        ],
      };

      final client =
          MockClient((_) async => http.Response(jsonEncode(payload), 200));
      final thread = await SourceClient.forSource(
        src(Network.mastodon, {'instance': 'mastodon.social'}),
        client,
      ).fetchThread(itemWith(network: Network.mastodon, nativeId: '1'));

      expect(thread.replies.map((e) => e.item.text),
          ['direct reply', 'reply to the reply', 'another direct reply']);
      expect(thread.replies.map((e) => e.depth), [0, 1, 0]);
    });
  });

  group('Bluesky thread', () {
    test('flattens nested replies and skips deleted stubs', () async {
      Map<String, dynamic> post(String cid, String text) => {
            'uri': 'at://did/app.bsky.feed.post/$cid',
            'cid': cid,
            'author': {'handle': 'a.bsky.social', 'displayName': 'A'},
            'record': {'text': text, 'createdAt': '2026-08-01T10:00:00.000Z'},
          };

      final payload = {
        'thread': {
          'post': post('root', 'root post'),
          'replies': [
            {
              'post': post('r1', 'first reply'),
              'replies': [
                {'post': post('r2', 'nested reply')},
              ],
            },
            {'blocked': true},
            {'post': post('r3', 'second reply')},
          ],
        },
      };

      final client =
          MockClient((_) async => http.Response(jsonEncode(payload), 200));
      final thread = await SourceClient.forSource(
        src(Network.bluesky, {'handle': 'a.bsky.social'}),
        client,
      ).fetchThread(itemWith(
          network: Network.bluesky, nativeId: 'at://did/app.bsky.feed.post/root'));

      expect(thread.replies.map((e) => e.item.text),
          ['first reply', 'nested reply', 'second reply']);
      expect(thread.replies.map((e) => e.depth), [0, 1, 0]);
    });
  });

  group('graceful degradation', () {
    test('RSS has no thread to fetch', () async {
      final client = MockClient((_) async => http.Response('', 200));
      final thread = await SourceClient.forSource(
        src(Network.rss, {'url': 'https://example.com/feed'}),
        client,
      ).fetchThread(itemWith(network: Network.rss, url: 'https://example.com/1'));

      expect(thread.isEmpty, isTrue);
    });

    test('a failed thread fetch returns nothing rather than throwing',
        () async {
      final client = MockClient((_) async => http.Response('nope', 500));
      final thread = await SourceClient.forSource(
        src(Network.mastodon, {'instance': 'mastodon.social'}),
        client,
      ).fetchThread(itemWith(network: Network.mastodon, nativeId: '1'));

      expect(thread.isEmpty, isTrue);
    });

    test('an item with no native id cannot be threaded', () async {
      final client = MockClient((_) async => http.Response('{}', 200));
      final thread = await SourceClient.forSource(
        src(Network.bluesky, {'handle': 'a.bsky.social'}),
        client,
      ).fetchThread(itemWith(network: Network.bluesky));

      expect(thread.isEmpty, isTrue);
    });
  });

  group('content warnings', () {
    test('a Mastodon spoiler hides the body until revealed', () async {
      final payload = [
        {
          'id': '1',
          'created_at': '2026-08-06T10:00:00.000Z',
          'content': '<p>the spoilery part</p>',
          'spoiler_text': 'Season finale',
          'sensitive': true,
          'account': {'display_name': 'A', 'acct': 'a', 'username': 'a'},
          'media_attachments': [],
        },
      ];
      final client =
          MockClient((_) async => http.Response(jsonEncode(payload), 200));

      final items = await SourceClient.forSource(
        src(Network.mastodon, {'instance': 'mastodon.social'}),
        client,
      ).fetchLatest();

      expect(items.single.contentWarning, 'Season finale');
      expect(items.single.sensitive, isTrue);
      expect(items.single.needsReveal, isTrue);
      // The text is still carried, just not shown until the user asks.
      expect(items.single.text, 'the spoilery part');
    });

    test('sensitive without a warning still needs revealing', () async {
      final payload = [
        {
          'id': '2',
          'created_at': '2026-08-06T10:00:00.000Z',
          'content': '<p>no warning text</p>',
          'spoiler_text': '',
          'sensitive': true,
          'account': {'display_name': 'A', 'acct': 'a', 'username': 'a'},
          'media_attachments': [],
        },
      ];
      final client =
          MockClient((_) async => http.Response(jsonEncode(payload), 200));

      final items = await SourceClient.forSource(
        src(Network.mastodon, {'instance': 'mastodon.social'}),
        client,
      ).fetchLatest();

      expect(items.single.contentWarning, isNull);
      expect(items.single.needsReveal, isTrue);
    });

    test('an ordinary post needs no reveal', () async {
      final payload = [
        {
          'id': '3',
          'created_at': '2026-08-06T10:00:00.000Z',
          'content': '<p>just a post</p>',
          'account': {'display_name': 'A', 'acct': 'a', 'username': 'a'},
          'media_attachments': [],
        },
      ];
      final client =
          MockClient((_) async => http.Response(jsonEncode(payload), 200));

      final items = await SourceClient.forSource(
        src(Network.mastodon, {'instance': 'mastodon.social'}),
        client,
      ).fetchLatest();

      expect(items.single.needsReveal, isFalse);
    });
  });

  group('FeedItem.body', () {
    test('prefers the untruncated text when present', () {
      final item = FeedItem(
        id: 'x',
        sourceId: 's',
        network: Network.rss,
        author: 'a',
        text: 'short teaser…',
        fullText: 'the entire article body',
        createdAt: DateTime.utc(2026),
      );
      expect(item.body, 'the entire article body');
    });

    test('falls back to the timeline text', () {
      final item = FeedItem(
        id: 'x',
        sourceId: 's',
        network: Network.mastodon,
        author: 'a',
        text: 'just this',
        createdAt: DateTime.utc(2026),
      );
      expect(item.body, 'just this');
    });
  });
}
