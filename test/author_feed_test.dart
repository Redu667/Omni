import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_item.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/source_client.dart';

FeedSource src(Network network, Map<String, String> params) =>
    FeedSource(id: 's', network: network, displayName: 'T', params: params);

FeedItem by(Network network, {String? handle, String author = 'someone'}) =>
    FeedItem(
      id: 's:1',
      sourceId: 's',
      network: network,
      author: author,
      handle: handle,
      createdAt: DateTime.utc(2026, 8, 1),
    );

void main() {
  test('RSS has no author feed to offer', () {
    final client = SourceClient.forSource(
        src(Network.rss, {'url': 'https://e.com/f'}),
        MockClient((_) async => http.Response('', 200)));

    expect(client.supportsAuthorFeed, isFalse);
  });

  test('Mastodon resolves the handle before fetching statuses', () async {
    final paths = <String>[];
    final client = MockClient((req) async {
      paths.add(req.url.path);
      if (req.url.path.contains('lookup')) {
        expect(req.url.queryParameters['acct'], 'alice@example.social');
        return http.Response(jsonEncode({'id': '42'}), 200);
      }
      return http.Response(
          jsonEncode([
            {
              'id': '9',
              'created_at': '2026-08-05T10:00:00.000Z',
              'content': '<p>a post by alice</p>',
              'account': {
                'display_name': 'Alice',
                'acct': 'alice@example.social',
                'username': 'alice',
              },
              'media_attachments': [],
            },
          ]),
          200);
    });

    final posts = await SourceClient.forSource(
      src(Network.mastodon, {'instance': 'mastodon.social'}),
      client,
    ).fetchAuthorPosts(by(Network.mastodon, handle: '@alice@example.social'));

    expect(paths.first, '/api/v1/accounts/lookup');
    expect(paths.last, '/api/v1/accounts/42/statuses');
    expect(posts.single.text, 'a post by alice');
  });

  test('Mastodon reports an unknown handle rather than returning nothing',
      () async {
    final client = MockClient((_) async => http.Response('nope', 404));

    expect(
      SourceClient.forSource(
        src(Network.mastodon, {'instance': 'mastodon.social'}),
        client,
      ).fetchAuthorPosts(by(Network.mastodon, handle: '@ghost@example.social')),
      throwsA(predicate((e) =>
          e is SourceFetchException && e.message.contains('Could not find'))),
    );
  });

  test('Bluesky asks for the author feed by handle', () async {
    late Uri requested;
    final client = MockClient((req) async {
      requested = req.url;
      return http.Response(
          jsonEncode({
            'feed': [
              {
                'post': {
                  'uri': 'at://did/app.bsky.feed.post/1',
                  'cid': 'c1',
                  'author': {'handle': 'alice.bsky.social', 'displayName': 'A'},
                  'record': {
                    'text': 'hello',
                    'createdAt': '2026-08-05T10:00:00.000Z',
                  },
                },
              },
            ],
          }),
          200);
    });

    final posts = await SourceClient.forSource(
      src(Network.bluesky, {'handle': 'someone.bsky.social'}),
      client,
    ).fetchAuthorPosts(by(Network.bluesky, handle: '@alice.bsky.social'));

    expect(requested.queryParameters['actor'], 'alice.bsky.social');
    expect(posts.single.text, 'hello');
  });

  test('Reddit asks for the user\'s submitted posts', () async {
    final paths = <String>[];
    final client = MockClient((req) async {
      paths.add(req.url.path);
      return http.Response(
          jsonEncode({
            'data': {
              'children': [
                {
                  'data': {
                    'name': 't3_a',
                    'title': 'their post',
                    'author': 'lawyer',
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

    final posts = await SourceClient.forSource(
      src(Network.reddit, {'subreddit': 'law'}),
      client,
    ).fetchAuthorPosts(by(Network.reddit, author: 'u/lawyer'));

    expect(paths.first, '/user/lawyer/submitted.json');
    expect(posts.single.title, 'their post');
  });

  test('a deleted Reddit author has nothing to show', () async {
    final client = MockClient((_) async => http.Response('{}', 200));

    expect(
      await SourceClient.forSource(
        src(Network.reddit, {'subreddit': 'law'}),
        client,
      ).fetchAuthorPosts(by(Network.reddit, author: '[deleted]')),
      isEmpty,
    );
  });

  test('an item with no handle cannot open a profile', () async {
    final client = MockClient((_) async => http.Response('{}', 200));

    expect(
      await SourceClient.forSource(
        src(Network.bluesky, {'handle': 'a.bsky.social'}),
        client,
      ).fetchAuthorPosts(by(Network.bluesky)),
      isEmpty,
    );
  });
}
