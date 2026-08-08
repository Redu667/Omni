import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_item.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/source_client.dart';
import 'package:omni/services/twitter_guest_config.dart';

FeedSource xSource() => FeedSource(
      id: 's',
      network: Network.twitter,
      displayName: 'X',
      params: {'usernames': 'someone', 'mode': 'guest'},
    );

FeedItem focal(String id) => FeedItem(
      id: 's:$id',
      sourceId: 's',
      network: Network.twitter,
      author: 'Someone',
      nativeId: id,
      createdAt: DateTime.utc(2026, 8, 1),
    );

Map<String, dynamic> tweet(String id, String text) => {
      '__typename': 'Tweet',
      'rest_id': id,
      'core': {
        'user_results': {
          'result': {
            'legacy': {'name': 'User $id', 'screen_name': 'u$id'},
          },
        },
      },
      'legacy': {
        'id_str': id,
        'full_text': text,
        'created_at': 'Sat Aug 01 10:00:00 +0000 2026',
      },
    };

Map<String, dynamic> tweetEntry(String id, String text) => {
      'entryId': 'tweet-$id',
      'content': {
        'itemContent': {
          'tweet_results': {'result': tweet(id, text)},
        },
      },
    };

Map<String, dynamic> conversationEntry(List<(String, String)> chain) => {
      'entryId': 'conversationthread-1',
      'content': {
        'items': [
          for (final (id, text) in chain)
            {
              'item': {
                'itemContent': {
                  'tweet_results': {'result': tweet(id, text)},
                },
              },
            },
        ],
      },
    };

Map<String, dynamic> conversation(List<Map<String, dynamic>> entries) => {
      'data': {
        'threaded_conversation_with_injections_v2': {
          'instructions': [
            {'type': 'TimelineAddEntries', 'entries': entries},
          ],
        },
      },
    };

/// Answers the guest-token activation and then the GraphQL call.
http.Client server(Object graphqlBody, {int graphqlStatus = 200}) =>
    MockClient((req) async {
      if (req.url.path.contains('guest/activate')) {
        return http.Response(jsonEncode({'guest_token': 'g'}), 200);
      }
      return http.Response.bytes(
          utf8.encode(jsonEncode(graphqlBody)), graphqlStatus);
    });

Future<PostThread> threadOf(Object body, {String id = '100'}) =>
    SourceClient.forSource(xSource(), server(body),
            twitterConfig: TwitterGuestConfig.defaults)
        .fetchThread(focal(id));

void main() {
  test('tweets before the focal one are its ancestors', () async {
    final thread = await threadOf(conversation([
      tweetEntry('98', 'the original'),
      tweetEntry('99', 'a reply to it'),
      tweetEntry('100', 'the tweet being read'),
      tweetEntry('101', 'someone answering'),
    ]));

    expect(thread.ancestors.map((i) => i.text),
        ['the original', 'a reply to it']);
    expect(thread.replies.map((e) => e.item.text), ['someone answering']);
  });

  test('the focal tweet is not repeated in its own thread', () async {
    final thread = await threadOf(conversation([
      tweetEntry('100', 'the tweet being read'),
      tweetEntry('101', 'a reply'),
    ]));

    expect(thread.ancestors, isEmpty);
    expect(thread.replies.single.item.nativeId, '101');
  });

  test('a conversation module deepens as the chain goes on', () async {
    final thread = await threadOf(conversation([
      tweetEntry('100', 'focal'),
      conversationEntry([
        ('101', 'a reply'),
        ('102', 'a reply to the reply'),
        ('103', 'deeper still'),
      ]),
    ]));

    expect(thread.replies.map((e) => e.item.text),
        ['a reply', 'a reply to the reply', 'deeper still']);
    expect(thread.replies.map((e) => e.depth), [0, 1, 2]);
  });

  test('a module that repeats the focal tweet does not indent past it',
      () async {
    final thread = await threadOf(conversation([
      conversationEntry([
        ('100', 'focal'),
        ('101', 'a reply'),
      ]),
    ]));

    expect(thread.replies.single.item.nativeId, '101');
    expect(thread.replies.single.depth, 0);
  });

  test('cursor entries are skipped', () async {
    final thread = await threadOf(conversation([
      tweetEntry('100', 'focal'),
      {'entryId': 'cursor-bottom-1', 'content': {'value': 'next'}},
      tweetEntry('101', 'a reply'),
    ]));

    expect(thread.replies, hasLength(1));
  });

  test('a stale query ID leaves the post readable rather than failing',
      () async {
    final thread = await threadOf({'errors': [{'message': 'unknown query'}]});
    expect(thread.isEmpty, isTrue);
  });

  test('a rejected request is not an error either', () async {
    final client = MockClient((req) async =>
        req.url.path.contains('guest/activate')
            ? http.Response(jsonEncode({'guest_token': 'g'}), 200)
            : http.Response('nope', 403));

    final thread = await SourceClient.forSource(xSource(), client,
            twitterConfig: TwitterGuestConfig.defaults)
        .fetchThread(focal('100'));

    expect(thread.isEmpty, isTrue);
  });

  test('a post with no id has nothing to ask about', () async {
    var called = false;
    final client = MockClient((_) async {
      called = true;
      return http.Response('{}', 200);
    });

    final thread = await SourceClient.forSource(xSource(), client,
            twitterConfig: TwitterGuestConfig.defaults)
        .fetchThread(FeedItem(
      id: 's:1',
      sourceId: 's',
      network: Network.twitter,
      author: 'Someone',
      createdAt: DateTime.utc(2026, 8, 1),
    ));

    expect(thread.isEmpty, isTrue);
    expect(called, isFalse);
  });

  test('the TweetDetail query ID round-trips through settings', () {
    final edited = TwitterGuestConfig.defaults.copyWith(
      tweetDetailQueryId: 'custom-id',
      homeTimelineQueryId: 'home-id',
    );
    final restored = TwitterGuestConfig.fromJson(edited.toJson());

    expect(restored.tweetDetailQueryId, 'custom-id');
    // The home timeline ID used to be dropped on save.
    expect(restored.homeTimelineQueryId, 'home-id');
  });
}
