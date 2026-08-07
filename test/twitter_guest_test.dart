import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/source_client.dart';
import 'package:omni/services/twitter_guest_client.dart';
import 'package:omni/services/twitter_guest_config.dart';
import 'package:omni/services/twitter_guest_session.dart';
import 'package:omni/util/text.dart';

FeedSource twitterSource([Map<String, String>? extra]) => FeedSource(
      id: 'tw',
      network: Network.twitter,
      displayName: 'X · nasa',
      params: {'mode': 'guest', 'usernames': 'nasa', ...?extra},
    );

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Renders a UTC instant in the format X stamps on tweets.
String twitterStamp(DateTime utc) =>
    'Mon ${_months[utc.month - 1]} ${utc.day.toString().padLeft(2, '0')} '
    '${utc.hour.toString().padLeft(2, '0')}:'
    '${utc.minute.toString().padLeft(2, '0')}:'
    '${utc.second.toString().padLeft(2, '0')} +0000 ${utc.year}';

DateTime daysAgo(int days) =>
    DateTime.now().toUtc().subtract(Duration(days: days));

/// Minimal stand-in for the shape X's UserTweets response actually has.
///
/// [createdAt] defaults to yesterday rather than a fixed date, so the
/// staleness guard in the client doesn't turn the whole suite red once
/// enough wall-clock time passes.
Map<String, dynamic> tweetEntry({
  required String id,
  required String text,
  String name = 'NASA',
  String screenName = 'NASA',
  String? createdAt,
  Map<String, dynamic>? extraLegacy,
  String? typename,
  Map<String, dynamic>? user,
}) {
  createdAt ??= twitterStamp(daysAgo(1));
  final tweet = <String, dynamic>{
    'rest_id': id,
    'core': {
      'user_results': {
        'result': user ??
            {
              'legacy': {
                'name': name,
                'screen_name': screenName,
                'profile_image_url_https': 'https://pbs/avatar.jpg',
              },
            },
      },
    },
    'legacy': {
      'full_text': text,
      'created_at': createdAt,
      'favorite_count': 100,
      'retweet_count': 20,
      'reply_count': 5,
      ...?extraLegacy,
    },
  };

  return {
    'entryId': 'tweet-$id',
    'content': {
      'itemContent': {
        'tweet_results': {
          'result': typename == 'TweetWithVisibilityResults'
              ? {'__typename': typename, 'tweet': tweet}
              : tweet,
        },
      },
    },
  };
}

Map<String, dynamic> timelineBody(List<Map<String, dynamic>> entries) => {
      'data': {
        'user': {
          'result': {
            'timeline_v2': {
              'timeline': {
                'instructions': [
                  {'type': 'TimelineAddEntries', 'entries': entries},
                ],
              },
            },
          },
        },
      },
    };

/// X serves UTF-8, and tweets are full of emoji and non-Latin scripts, so
/// mocks must encode as UTF-8 bytes rather than the Latin-1 default.
http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

/// Routes the three calls a guest fetch makes: activate, resolve, timeline.
MockClient guestMock({
  required Map<String, dynamic> timeline,
  Map<String, dynamic>? userLookup,
  int activateStatus = 200,
  int graphqlStatus = 200,
  void Function(http.Request req)? onGraphql,
}) {
  return MockClient((req) async {
    if (req.url.path == '/1.1/guest/activate.json') {
      return jsonResponse({'guest_token': 'g123'}, activateStatus);
    }
    onGraphql?.call(req);
    if (graphqlStatus != 200) {
      return jsonResponse({
        'errors': [
          {'message': 'nope'},
        ],
      }, graphqlStatus);
    }
    if (req.url.path.contains('UserByScreenName')) {
      return jsonResponse(userLookup ??
          {
            'data': {
              'user': {'result': {'rest_id': '11348282'}},
            },
          });
    }
    return jsonResponse(timeline);
  });
}

void main() {
  group('parseTwitterDate', () {
    test('parses X\'s month-first format', () {
      expect(parseTwitterDate('Wed Aug 05 20:15:00 +0000 2026'),
          DateTime.utc(2026, 8, 5, 20, 15));
    });

    test('applies the timezone offset', () {
      expect(parseTwitterDate('Wed Aug 05 20:15:00 +0200 2026'),
          DateTime.utc(2026, 8, 5, 18, 15));
    });

    test('falls back to ISO and rejects junk', () {
      expect(parseTwitterDate('2026-08-05T10:00:00Z'),
          DateTime.utc(2026, 8, 5, 10));
      expect(parseTwitterDate('gibberish'), isNull);
      expect(parseTwitterDate(null), isNull);
    });
  });

  group('TwitterGuestSession', () {
    test('activates once and caches the token', () async {
      var activations = 0;
      final client = MockClient((req) async {
        activations++;
        return jsonResponse({'guest_token': 'g1'});
      });
      final session = TwitterGuestSession();

      expect(await session.token(client, TwitterGuestConfig.defaults), 'g1');
      expect(await session.token(client, TwitterGuestConfig.defaults), 'g1');
      expect(activations, 1);
    });

    test('re-activates when forced', () async {
      var activations = 0;
      final client = MockClient((req) async {
        activations++;
        return jsonResponse({'guest_token': 'g$activations'});
      });
      final session = TwitterGuestSession();

      await session.token(client, TwitterGuestConfig.defaults);
      final second = await session.token(client, TwitterGuestConfig.defaults,
          forceRefresh: true);
      expect(second, 'g2');
      expect(activations, 2);
    });

    test('explains a rejected bearer token', () async {
      final client = MockClient((_) async => http.Response('no', 403));
      expect(
        TwitterGuestSession().token(client, TwitterGuestConfig.defaults),
        throwsA(predicate((e) =>
            e is TwitterGuestException && e.message.contains('bearer token'))),
      );
    });
  });

  group('TwitterGuestClient', () {
    Future<List<dynamic>> fetch(MockClient client, [FeedSource? source]) =>
        TwitterGuestClient(
          source ?? twitterSource(),
          client,
          config: TwitterGuestConfig.defaults,
          session: TwitterGuestSession(),
        ).fetchLatest();

    test('sends guest token and bearer on the GraphQL call', () async {
      final requests = <http.Request>[];
      final client = guestMock(
        timeline: timelineBody([tweetEntry(id: '1', text: 'hi')]),
        onGraphql: requests.add,
      );

      await fetch(client);

      expect(requests, isNotEmpty);
      expect(requests.first.headers['x-guest-token'], 'g123');
      expect(requests.first.headers['Authorization'],
          'Bearer ${TwitterGuestConfig.defaultBearerToken}');
      expect(requests.first.url.path,
          contains(TwitterGuestConfig.defaultUserByScreenNameQueryId));
      expect(requests.last.url.queryParameters['features'], isNotEmpty);
    });

    test('parses a tweet into a FeedItem', () async {
      final client = guestMock(
        timeline: timelineBody([
          tweetEntry(
            id: '999',
            text: 'Hello from orbit https://t.co/abc',
            createdAt: 'Wed Aug 05 20:15:00 +0000 2026',
            extraLegacy: {
              'entities': {
                'urls': [
                  {
                    'url': 'https://t.co/abc',
                    'expanded_url': 'https://nasa.gov/live',
                  },
                ],
              },
              'extended_entities': {
                'media': [
                  {
                    'media_url_https': 'https://pbs/photo.jpg',
                    'type': 'photo',
                    'url': 'https://t.co/media',
                  },
                ],
              },
            },
          ),
        ]),
      );

      final items = await fetch(client);
      expect(items, hasLength(1));
      final item = items.single;
      expect(item.author, 'NASA');
      expect(item.handle, '@NASA');
      expect(item.text, 'Hello from orbit https://nasa.gov/live');
      expect(item.url, 'https://x.com/NASA/status/999');
      expect(item.imageUrls, ['https://pbs/photo.jpg']);
      expect(item.likes, 100);
      expect(item.reposts, 20);
      expect(item.createdAt, DateTime.utc(2026, 8, 5, 20, 15));
      expect(item.network, Network.twitter);
    });

    test('unwraps limited-visibility tweets', () async {
      final client = guestMock(
        timeline: timelineBody([
          tweetEntry(
              id: '2',
              text: 'restricted but readable',
              typename: 'TweetWithVisibilityResults'),
        ]),
      );

      final items = await fetch(client);
      expect(items.single.text, 'restricted but readable');
    });

    test('attributes retweets to the booster', () async {
      final inner = tweetEntry(id: '3', text: 'original', name: 'Author', screenName: 'author');
      final innerTweet = inner['content']['itemContent']['tweet_results']['result'];

      final client = guestMock(
        timeline: timelineBody([
          tweetEntry(
            id: '4',
            text: 'RT @author original',
            name: 'Booster',
            screenName: 'booster',
            extraLegacy: {
              'retweeted_status_result': {'result': innerTweet},
            },
          ),
        ]),
      );

      final items = await fetch(client);
      expect(items.single.repostedBy, 'Booster');
      expect(items.single.author, 'Author');
      expect(items.single.text, 'original');
    });

    test('prefers the long-form body over the truncated one', () async {
      final entry = tweetEntry(id: '5', text: 'truncated version…');
      entry['content']['itemContent']['tweet_results']['result']['note_tweet'] =
          {
        'note_tweet_results': {
          'result': {'text': 'the complete long-form post'},
        },
      };

      final items = await fetch(guestMock(timeline: timelineBody([entry])));
      expect(items.single.text, 'the complete long-form post');
    });

    test('decodes emoji and non-Latin text', () async {
      final client = guestMock(
        timeline: timelineBody([
          tweetEntry(
              id: '11',
              text: '🚀 発射しました — de órbita ✨',
              name: 'NASA 宇宙'),
        ]),
      );

      final item = (await fetch(client)).single;
      expect(item.text, '🚀 発射しました — de órbita ✨');
      expect(item.author, 'NASA 宇宙');
    });

    test('reads user fields from the newer core shape', () async {
      final client = guestMock(
        timeline: timelineBody([
          tweetEntry(id: '6', text: 'new shape', user: {
            'core': {'name': 'New Shape', 'screen_name': 'newshape'},
            'avatar': {'image_url': 'https://pbs/new.jpg'},
          }),
        ]),
      );

      final item = (await fetch(client)).single;
      expect(item.author, 'New Shape');
      expect(item.handle, '@newshape');
      expect(item.avatarUrl, 'https://pbs/new.jpg');
    });

    test('refuses to pass off a stale timeline as current', () async {
      // X keeps answering 200 while quietly serving an old slice of the
      // timeline; year-old posts must not appear as if they were fresh.
      final client = guestMock(
        timeline: timelineBody([
          tweetEntry(
              id: '20',
              text: 'ancient history',
              createdAt: twitterStamp(daysAgo(400))),
        ]),
      );

      expect(
        fetch(client),
        throwsA(predicate((e) =>
            e is SourceFetchException &&
            e.message.contains('stale timeline') &&
            e.message.contains('query IDs'))),
      );
    });

    test('accepts a timeline that is merely quiet, not stale', () async {
      // 40 days old: inside the 45-day threshold, so a low-traffic account
      // is not mistaken for a degraded connection.
      final client = guestMock(
        timeline: timelineBody([
          tweetEntry(
              id: '21',
              text: 'still alive',
              createdAt: twitterStamp(daysAgo(40))),
        ]),
      );

      expect((await fetch(client)).single.text, 'still alive');
    });

    test('returns newest first even when X does not', () async {
      final client = guestMock(
        timeline: timelineBody([
          tweetEntry(
              id: '22', text: 'older', createdAt: twitterStamp(daysAgo(5))),
          tweetEntry(
              id: '23', text: 'newer', createdAt: twitterStamp(daysAgo(1))),
        ]),
      );

      final items = await fetch(client);
      expect(items.map((i) => i.text), ['newer', 'older']);
    });

    test('skips cursor entries', () async {
      final client = guestMock(
        timeline: timelineBody([
          {'entryId': 'cursor-top-123', 'content': {'value': 'x'}},
          tweetEntry(id: '7', text: 'real tweet'),
        ]),
      );
      expect(await fetch(client), hasLength(1));
    });

    test('flattens self-thread modules', () async {
      final part = tweetEntry(id: '8', text: 'part one');
      final client = guestMock(
        timeline: timelineBody([
          {
            'entryId': 'profile-conversation-1',
            'content': {
              'items': [
                {
                  'item': {
                    'itemContent': {
                      'tweet_results': {
                        'result': part['content']['itemContent']
                            ['tweet_results']['result'],
                      },
                    },
                  },
                },
              ],
            },
          },
        ]),
      );
      expect((await fetch(client)).single.text, 'part one');
    });

    test('calls a rotated query ID out by name', () async {
      final client = guestMock(
          timeline: const {}, graphqlStatus: 404);

      expect(
        fetch(client),
        throwsA(predicate((e) =>
            e is SourceFetchException &&
            e.message.contains('rotated') &&
            e.message.contains('UserByScreenName'))),
      );
    });

    test('explains a feature-flag mismatch', () async {
      final client = guestMock(timeline: const {}, graphqlStatus: 400);

      expect(
        fetch(client),
        throwsA(predicate((e) =>
            e is SourceFetchException &&
            e.message.contains('feature-flag'))),
      );
    });

    test('explains rate limiting', () async {
      final client = guestMock(timeline: const {}, graphqlStatus: 429);

      expect(
        fetch(client),
        throwsA(predicate((e) =>
            e is SourceFetchException && e.message.contains('rate limited'))),
      );
    });

    test('reports a missing account clearly', () async {
      final client = guestMock(
        timeline: const {},
        userLookup: {'data': {'user': {}}},
      );

      expect(
        fetch(client),
        throwsA(predicate((e) =>
            e is SourceFetchException && e.message.contains('no such account'))),
      );
    });

    test('retries once with a fresh token after an auth failure', () async {
      var graphqlCalls = 0;
      var activations = 0;
      final client = MockClient((req) async {
        if (req.url.path == '/1.1/guest/activate.json') {
          activations++;
          return jsonResponse({'guest_token': 'g$activations'});
        }
        graphqlCalls++;
        if (graphqlCalls == 1) return http.Response('expired', 401);
        if (req.url.path.contains('UserByScreenName')) {
          return jsonResponse({
            'data': {'user': {'result': {'rest_id': '1'}}},
          });
        }
        return jsonResponse(
            timelineBody([tweetEntry(id: '9', text: 'after retry')]));
      });

      final items = await fetch(client);
      expect(activations, 2);
      expect(items.single.text, 'after retry');
    });

    test('keeps working accounts when one of several fails', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/1.1/guest/activate.json') {
          return jsonResponse({'guest_token': 'g1'});
        }
        if (req.url.path.contains('UserByScreenName')) {
          final vars = jsonDecode(req.url.queryParameters['variables']!)
              as Map<String, dynamic>;
          if (vars['screen_name'] == 'ghost') {
            return jsonResponse({'data': {'user': {}}});
          }
          return jsonResponse({
            'data': {'user': {'result': {'rest_id': '1'}}},
          });
        }
        return jsonResponse(
            timelineBody([tweetEntry(id: '10', text: 'survivor')]));
      });

      final items = await fetch(
          client, twitterSource({'usernames': 'nasa, ghost'}));
      expect(items.single.text, 'survivor');
    });
  });

  group('routing', () {
    test('guest mode is the default for Twitter sources', () {
      final client = MockClient((_) async => http.Response('{}', 200));
      expect(
        SourceClient.forSource(
            FeedSource(
                id: 't',
                network: Network.twitter,
                displayName: 'X',
                params: {'usernames': 'nasa'}),
            client),
        isA<TwitterGuestClient>(),
      );
    });

    test('official mode opts into the paid API client', () {
      final client = MockClient((_) async => http.Response('{}', 200));
      expect(
        SourceClient.forSource(
            FeedSource(
                id: 't',
                network: Network.twitter,
                displayName: 'X',
                params: {'mode': 'official', 'usernames': 'nasa'}),
            client),
        isNot(isA<TwitterGuestClient>()),
      );
    });
  });

  group('TwitterGuestConfig', () {
    test('round-trips through JSON', () {
      const config = TwitterGuestConfig(
        bearerToken: 'b',
        userByScreenNameQueryId: 'q1',
        userTweetsQueryId: 'q2',
        featuresJson: '{"a":true}',
      );
      final restored = TwitterGuestConfig.fromJson(config.toJson());
      expect(restored.userTweetsQueryId, 'q2');
      expect(restored.features, {'a': true});
    });

    test('survives malformed feature JSON', () {
      const config = TwitterGuestConfig(
        bearerToken: 'b',
        userByScreenNameQueryId: 'q1',
        userTweetsQueryId: 'q2',
        featuresJson: 'not json',
      );
      expect(config.features, isEmpty);
      expect(config.featuresJsonIsValid, isFalse);
    });

    test('ships valid default feature flags', () {
      expect(TwitterGuestConfig.defaults.featuresJsonIsValid, isTrue);
      expect(TwitterGuestConfig.defaults.features, isNotEmpty);
    });
  });
}
