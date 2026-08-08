import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/feed_repository.dart';
import 'package:omni/services/source_client.dart';

FeedSource src(String id, Network network, Map<String, String> params) =>
    FeedSource(id: id, network: network, displayName: id, params: params);

({List<Uri> seen, http.Client client}) recorder(Object body,
    {int status = 200}) {
  final seen = <Uri>[];
  final client = MockClient((req) async {
    seen.add(req.url);
    return http.Response.bytes(utf8.encode(jsonEncode(body)), status);
  });
  return (seen: seen, client: client);
}

final _bskyPost = {
  'uri': 'at://did/app.bsky.feed.post/1',
  'cid': 'c1',
  'author': {'handle': 'a.bsky.social', 'displayName': 'A'},
  'record': {'text': 'a match', 'createdAt': '2026-08-05T10:00:00.000Z'},
};

final _mastoStatus = {
  'id': '1',
  'created_at': '2026-08-05T10:00:00.000Z',
  'content': '<p>a match</p>',
  'account': {'display_name': 'A', 'acct': 'a', 'username': 'a'},
  'media_attachments': [],
};

/// A day older than [_bskyPost] and [_mastoStatus], so merge ordering is
/// unambiguous rather than a coin flip between equal timestamps.
Map<String, dynamic> redditListing(String title) => {
      'data': {
        'children': [
          {
            'data': {
              'name': 't3_1',
              'title': title,
              'author': 'someone',
              'permalink': '/r/law/comments/1/a/',
              'subreddit': 'law',
              'created_utc': 1785837600,
            },
          },
        ],
        'after': null,
      },
    };

void main() {
  group('Bluesky', () {
    test('searches posts on the public host', () async {
      final r = recorder({
        'posts': [_bskyPost],
      });
      final found = await SourceClient.forSource(
              src('b', Network.bluesky, {'handle': 'a.bsky.social'}), r.client)
          .search('rockets');

      expect(found.single.text, 'a match');
      expect(r.seen.single.path, endsWith('app.bsky.feed.searchPosts'));
      expect(r.seen.single.queryParameters['q'], 'rockets');
      expect(r.seen.single.host, 'public.api.bsky.app');
    });

    test('a failure yields nothing rather than an error', () async {
      final r = recorder(const {}, status: 500);
      expect(
          await SourceClient.forSource(
                  src('b', Network.bluesky, {'handle': 'a.bsky.social'}),
                  r.client)
              .search('rockets'),
          isEmpty);
    });
  });

  group('Mastodon', () {
    test('a signed-in source searches statuses', () async {
      final r = recorder({
        'statuses': [_mastoStatus],
      });
      final found = await SourceClient.forSource(
              src('m', Network.mastodon,
                  {'instance': 'mastodon.social', 'accessToken': 'tok'}),
              r.client)
          .search('rockets');

      expect(found, hasLength(1));
      expect(r.seen.single.path, '/api/v2/search');
      expect(r.seen.single.queryParameters['type'], 'statuses');
      // Making the instance resolve remote accounts mid-search is slow.
      expect(r.seen.single.queryParameters['resolve'], 'false');
    });

    test('a hashtag query uses the tag timeline, which is public', () async {
      final r = recorder([_mastoStatus]);
      final found = await SourceClient.forSource(
              src('m', Network.mastodon, {'instance': 'mastodon.social'}),
              r.client)
          .search('#photography');

      expect(found, hasLength(1));
      expect(r.seen.single.path, '/api/v1/timelines/tag/photography');
    });

    test('status search without a token asks nothing', () async {
      final r = recorder({'statuses': const []});
      final found = await SourceClient.forSource(
              src('m', Network.mastodon, {'instance': 'mastodon.social'}),
              r.client)
          .search('rockets');

      // Status search is authenticated on nearly every instance; a 401 in a
      // search box is worse than no results.
      expect(found, isEmpty);
      expect(r.seen, isEmpty);
    });

    test('a filtered result is left out of search too', () async {
      final r = recorder({
        'statuses': [
          {
            ..._mastoStatus,
            'filtered': [
              {
                'filter': {'id': '1', 'title': 'X', 'filter_action': 'hide'},
              },
            ],
          },
        ],
      });
      final found = await SourceClient.forSource(
              src('m', Network.mastodon,
                  {'instance': 'mastodon.social', 'accessToken': 'tok'}),
              r.client)
          .search('rockets');

      expect(found, isEmpty);
    });
  });

  group('Reddit', () {
    test('searches within the subreddit the source follows', () async {
      final r = recorder(redditListing('a match'));
      final found = await SourceClient.forSource(
              src('r', Network.reddit, {'subreddit': 'law'}), r.client)
          .search('injunction');

      expect(found.single.title, 'a match');
      expect(r.seen.single.path, '/r/law/search.json');
      expect(r.seen.single.queryParameters['q'], 'injunction');
      // Site-wide results would drown out the source the reader added.
      expect(r.seen.single.queryParameters['restrict_sr'], '1');
    });

    test('a block yields nothing rather than an error', () async {
      final r = recorder('<html>blocked</html>', status: 403);
      expect(
          await SourceClient.forSource(
                  src('r', Network.reddit, {'subreddit': 'law'}), r.client)
              .search('injunction'),
          isEmpty);
    });
  });

  group('which sources can be searched', () {
    final client = MockClient((_) async => http.Response('{}', 200));

    test('RSS and X cannot', () {
      for (final source in [
        src('f', Network.rss, {'url': 'https://example.com/feed'}),
        src('x', Network.twitter, {'usernames': 'nasa', 'mode': 'guest'}),
      ]) {
        expect(SourceClient.forSource(source, client).supportsSearch, isFalse,
            reason: source.id);
      }
    });

    test('the others can', () {
      for (final source in [
        src('m', Network.mastodon, {'instance': 'mastodon.social'}),
        src('b', Network.bluesky, {'handle': 'a.bsky.social'}),
        src('r', Network.reddit, {'subreddit': 'law'}),
      ]) {
        expect(SourceClient.forSource(source, client).supportsSearch, isTrue,
            reason: source.id);
      }
    });
  });

  group('across every source at once', () {
    test('merges results newest first and drops duplicates', () async {
      final repo = FeedRepository(httpClient: MockClient((req) async {
        if (req.url.path.contains('searchPosts')) {
          return http.Response(jsonEncode({'posts': [_bskyPost]}), 200);
        }
        return http.Response(jsonEncode(redditListing('a match')), 200);
      }));

      final found = await repo.search('rockets', [
        src('b', Network.bluesky, {'handle': 'a.bsky.social'}),
        src('r', Network.reddit, {'subreddit': 'law'}),
        src('f', Network.rss, {'url': 'https://example.com/feed'}),
      ]);

      expect(found, hasLength(2));
      expect(found.first.createdAt.isAfter(found.last.createdAt), isTrue);
    });

    test('one network failing does not lose the others', () async {
      final repo = FeedRepository(httpClient: MockClient((req) async {
        if (req.url.path.contains('searchPosts')) {
          return http.Response('boom', 500);
        }
        return http.Response(jsonEncode(redditListing('a match')), 200);
      }));

      final found = await repo.search('rockets', [
        src('b', Network.bluesky, {'handle': 'a.bsky.social'}),
        src('r', Network.reddit, {'subreddit': 'law'}),
      ]);

      expect(found, hasLength(1));
    });

    test('a disabled source is not asked', () async {
      var calls = 0;
      final repo = FeedRepository(httpClient: MockClient((_) async {
        calls++;
        return http.Response(jsonEncode({'posts': const []}), 200);
      }));

      await repo.search('rockets', [
        FeedSource(
          id: 'b',
          network: Network.bluesky,
          displayName: 'b',
          params: const {'handle': 'a.bsky.social'},
          enabled: false,
        ),
      ]);

      expect(calls, 0);
    });

    test('canSearch reflects what is configured', () {
      final repo = FeedRepository(
          httpClient: MockClient((_) async => http.Response('{}', 200)));

      expect(
          repo.canSearch([src('f', Network.rss, {'url': 'https://e/f'})]),
          isFalse);
      expect(
          repo.canSearch([
            src('f', Network.rss, {'url': 'https://e/f'}),
            src('r', Network.reddit, {'subreddit': 'law'}),
          ]),
          isTrue);
      expect(repo.canSearch(const <FeedSource>[]), isFalse);
    });
  });
}
