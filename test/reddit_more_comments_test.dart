import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_item.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/source_client.dart';

FeedSource redditSource([Map<String, String>? extra]) => FeedSource(
      id: 's',
      network: Network.reddit,
      displayName: 'r/law',
      params: {'subreddit': 'law', ...?extra},
    );

FeedItem post({String nativeId = '/r/law/comments/abc123/a_title/'}) =>
    FeedItem(
      id: 's:1',
      sourceId: 's',
      network: Network.reddit,
      author: 'u/someone',
      nativeId: nativeId,
      createdAt: DateTime.utc(2026, 8, 1),
    );

Map<String, dynamic> comment(String name, String body,
        {List<Map<String, dynamic>>? replies}) =>
    {
      'kind': 't1',
      'data': {
        'name': name,
        'author': 'user',
        'body': body,
        'score': 1,
        'created_utc': 1785924000,
        if (replies != null)
          'replies': {
            'data': {'children': replies},
          },
      },
    };

Map<String, dynamic> moreStub(List<String> ids, int count) => {
      'kind': 'more',
      'data': {'count': count, 'children': ids, 'name': 't1_more'},
    };

List<Object> threadPayload(List<Map<String, dynamic>> children) => [
      {
        'data': {'children': []},
      },
      {
        'data': {'children': children},
      },
    ];

void main() {
  group('truncated threads', () {
    test('a top-level "more" is carried rather than dropped', () async {
      final client = MockClient((_) async => http.Response.bytes(
          utf8.encode(jsonEncode(threadPayload([
            comment('t1_a', 'first'),
            moreStub(['x1', 'x2', 'x3'], 37),
          ]))),
          200));

      final thread = await SourceClient.forSource(redditSource(), client)
          .fetchThread(post());

      expect(thread.replies, hasLength(1));
      expect(thread.more, isNotNull);
      expect(thread.more!.count, 37);
      expect(thread.more!.ids, ['x1', 'x2', 'x3']);
      expect(thread.more!.depth, 0);
    });

    test('a nested "more" hangs off the comment it belongs to', () async {
      final client = MockClient((_) async => http.Response.bytes(
          utf8.encode(jsonEncode(threadPayload([
            comment('t1_a', 'parent', replies: [
              comment('t1_b', 'child'),
              moreStub(['y1'], 4),
            ]),
            comment('t1_c', 'sibling'),
          ]))),
          200));

      final thread = await SourceClient.forSource(redditSource(), client)
          .fetchThread(post());

      expect(thread.replies.map((e) => e.item.text),
          ['parent', 'child', 'sibling']);
      // The button belongs under "parent", not at the end of the thread.
      expect(thread.replies[0].more?.ids, ['y1']);
      expect(thread.replies[0].more?.depth, 1);
      expect(thread.replies[1].more, isNull);
      expect(thread.more, isNull);
    });

    test('a "continue this thread" stub with nothing to fetch is ignored',
        () async {
      final client = MockClient((_) async => http.Response.bytes(
          utf8.encode(jsonEncode(threadPayload([
            comment('t1_a', 'only'),
            moreStub(const [], 0),
          ]))),
          200));

      final thread = await SourceClient.forSource(redditSource(), client)
          .fetchThread(post());

      expect(thread.more, isNull);
    });
  });

  group('loading the rest', () {
    test('asks morechildren for the post, and rebuilds depth from parents',
        () async {
      Uri? asked;
      final client = MockClient((req) async {
        asked = req.url;
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'json': {
                'data': {
                  'things': [
                    comment('t1_x1', 'top level')
                      ..['data']['parent_id'] = 't3_abc123',
                    comment('t1_x2', 'a child of x1')
                      ..['data']['parent_id'] = 't1_x1',
                    comment('t1_x3', 'a grandchild')
                      ..['data']['parent_id'] = 't1_x2',
                  ],
                },
              },
            })),
            200);
      });

      final loaded = await SourceClient.forSource(redditSource(), client)
          .fetchMoreReplies(
              post(), const MoreReplies(count: 3, ids: ['x1', 'x2', 'x3']));

      expect(asked!.path, '/api/morechildren.json');
      expect(asked!.queryParameters['link_id'], 't3_abc123');
      expect(asked!.queryParameters['children'], 'x1,x2,x3');

      expect(loaded.map((e) => e.item.text),
          ['top level', 'a child of x1', 'a grandchild']);
      expect(loaded.map((e) => e.depth), [0, 1, 2]);
    });

    test('nested replies keep the depth the stub was found at', () async {
      final client = MockClient((_) async => http.Response.bytes(
          utf8.encode(jsonEncode({
            'json': {
              'data': {
                'things': [
                  comment('t1_y1', 'a deep reply')
                    ..['data']['parent_id'] = 't1_parent',
                ],
              },
            },
          })),
          200));

      final loaded = await SourceClient.forSource(redditSource(), client)
          .fetchMoreReplies(
              post(), const MoreReplies(count: 1, ids: ['y1'], depth: 3));

      expect(loaded.single.depth, 3);
    });

    test('a further "more" in the response attaches to its parent', () async {
      final client = MockClient((_) async => http.Response.bytes(
          utf8.encode(jsonEncode({
            'json': {
              'data': {
                'things': [
                  comment('t1_x1', 'loaded')
                    ..['data']['parent_id'] = 't3_abc123',
                  {
                    'kind': 'more',
                    'data': {
                      'count': 9,
                      'children': ['z1'],
                      'parent_id': 't1_x1',
                    },
                  },
                ],
              },
            },
          })),
          200));

      final loaded = await SourceClient.forSource(redditSource(), client)
          .fetchMoreReplies(
              post(), const MoreReplies(count: 1, ids: ['x1']));

      expect(loaded.single.more?.count, 9);
      expect(loaded.single.more?.ids, ['z1']);
    });

    test('an absolute permalink yields the same link_id as a bare path',
        () async {
      Uri? asked;
      final client = MockClient((req) async {
        asked = req.url;
        return http.Response('{"json":{"data":{"things":[]}}}', 200);
      });

      await SourceClient.forSource(redditSource(), client).fetchMoreReplies(
          post(nativeId: 'https://www.reddit.com/r/law/comments/abc123/t/'),
          const MoreReplies(count: 1, ids: ['x1']));

      expect(asked!.queryParameters['link_id'], 't3_abc123');
    });

    test('nothing to fetch means no request at all', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      });

      final loaded = await SourceClient.forSource(redditSource(), client)
          .fetchMoreReplies(post(), const MoreReplies(count: 0, ids: []));

      expect(loaded, isEmpty);
      expect(called, isFalse);
    });
  });

  group('comment sort', () {
    test('defaults to best, and passes a chosen sort through', () async {
      final asked = <String?>[];
      final client = MockClient((req) async {
        asked.add(req.url.queryParameters['sort']);
        return http.Response.bytes(
            utf8.encode(jsonEncode(threadPayload([]))), 200);
      });

      final reddit = SourceClient.forSource(redditSource(), client);
      await reddit.fetchThread(post());
      await reddit.fetchThread(post(), sort: 'new');
      // A sort this network doesn't offer falls back rather than being
      // handed to Reddit verbatim.
      await reddit.fetchThread(post(), sort: 'nonsense');

      expect(asked, ['confidence', 'new', 'confidence']);
    });

    test('offers sorts on Reddit and none on RSS', () {
      final client = MockClient((_) async => http.Response('{}', 200));
      expect(SourceClient.forSource(redditSource(), client).commentSorts,
          contains('top'));
      expect(
          SourceClient.forSource(
                  FeedSource(
                      id: 'r',
                      network: Network.rss,
                      displayName: 'Feed',
                      params: {'url': 'https://example.com/feed'}),
                  client)
              .commentSorts,
          isEmpty);
    });
  });

  group('listing time window', () {
    test('top sends the window, and hot never does', () async {
      final asked = <Uri>[];
      final client = MockClient((req) async {
        asked.add(req.url);
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'data': {'children': [], 'after': null},
            })),
            200);
      });

      await SourceClient.forSource(
              redditSource({'sort': 'top', 't': 'year'}), client)
          .fetchLatest();
      await SourceClient.forSource(
              redditSource({'sort': 'hot', 't': 'year'}), client)
          .fetchLatest();

      expect(asked.first.queryParameters['t'], 'year');
      expect(asked.last.queryParameters, isNot(contains('t')));
    });
  });
}
