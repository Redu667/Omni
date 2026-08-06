import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/feed_repository.dart';

void main() {
  test('merges sources chronologically and reports partial failures',
      () async {
    final mastodonStatuses = [
      {
        'id': 'old',
        'created_at': '2026-08-05T08:00:00.000Z',
        'content': '<p>older toot</p>',
        'account': {'display_name': 'A', 'acct': 'a', 'username': 'a'},
        'media_attachments': [],
      },
      {
        'id': 'new',
        'created_at': '2026-08-05T12:00:00.000Z',
        'content': '<p>newer toot</p>',
        'account': {'display_name': 'A', 'acct': 'a', 'username': 'a'},
        'media_attachments': [],
      },
    ];
    final redditListing = {
      'data': {
        'children': [
          {
            'data': {
              'name': 't3_mid',
              'title': 'middle post',
              'author': 'r',
              'subreddit': 'test',
              'permalink': '/r/test/mid/',
              // 2026-08-05T10:00:00Z
              'created_utc': 1785924000,
            },
          },
        ],
      },
    };

    final client = MockClient((req) async {
      if (req.url.host.contains('mastodon')) {
        return http.Response(jsonEncode(mastodonStatuses), 200);
      }
      if (req.url.host.contains('reddit')) {
        return http.Response(jsonEncode(redditListing), 200);
      }
      return http.Response('nope', 500);
    });

    final repo = FeedRepository(httpClient: client);
    final result = await repo.fetchAll([
      FeedSource(
          id: 's1',
          network: Network.mastodon,
          displayName: 'Mastodon',
          params: {'instance': 'mastodon.social'}),
      FeedSource(
          id: 's2',
          network: Network.reddit,
          displayName: 'Reddit',
          params: {'subreddit': 'test'}),
      FeedSource(
          id: 's3',
          network: Network.rss,
          displayName: 'Broken feed',
          params: {'url': 'https://broken.example.com/feed'}),
    ]);

    expect(result.items.map((i) => i.text.isNotEmpty ? i.text : i.title), [
      'newer toot',
      'middle post',
      'older toot',
    ]);
    expect(result.errors, hasLength(1));
    expect(result.errors.single, contains('Broken feed'));
  });

  test('skips disabled sources and dedupes identical ids', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response(
          jsonEncode([
            {
              'id': 'same',
              'created_at': '2026-08-05T12:00:00.000Z',
              'content': '<p>toot</p>',
              'account': {'display_name': 'A', 'acct': 'a', 'username': 'a'},
              'media_attachments': [],
            },
          ]),
          200);
    });

    final repo = FeedRepository(httpClient: client);
    final result = await repo.fetchAll([
      FeedSource(
          id: 'dup',
          network: Network.mastodon,
          displayName: 'One',
          params: {'instance': 'mastodon.social'}),
      FeedSource(
          id: 'dup',
          network: Network.mastodon,
          displayName: 'Clone',
          params: {'instance': 'mastodon.social'}),
      FeedSource(
          id: 'off',
          network: Network.mastodon,
          displayName: 'Disabled',
          params: {'instance': 'mastodon.social'},
          enabled: false),
    ]);

    expect(calls, 2);
    expect(result.items, hasLength(1));
  });
}
