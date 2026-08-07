import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/source_client.dart';

FeedSource redditSource([String subreddit = 'flutter']) => FeedSource(
      id: 'r',
      network: Network.reddit,
      displayName: 'r/$subreddit',
      params: {'subreddit': subreddit},
    );

String listingJson() => jsonEncode({
      'data': {
        'children': [
          {
            'data': {
              'name': 't3_a',
              'title': 'A post',
              'author': 'someone',
              'subreddit': 'flutter',
              'permalink': '/r/flutter/comments/a/',
              'created_utc': 1785924000,
            },
          },
        ],
      },
    });

Future<List<dynamic>> fetch(MockClient client, [FeedSource? source]) =>
    SourceClient.forSource(source ?? redditSource(), client).fetchLatest();

void main() {
  test('presents as a browser, since Reddit blocks clients that do not',
      () async {
    late http.Request captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response(listingJson(), 200);
    });

    await fetch(client);

    expect(captured.headers['User-Agent'], contains('Mozilla/5.0'));
    expect(captured.headers['Accept'], contains('application/json'));
  });

  test('falls back to old.reddit.com when the main host returns 403',
      () async {
    final hosts = <String>[];
    final client = MockClient((req) async {
      hosts.add(req.url.host);
      if (req.url.host == 'www.reddit.com') {
        return http.Response('blocked', 403);
      }
      return http.Response(listingJson(), 200);
    });

    final items = await fetch(client);

    expect(hosts, ['www.reddit.com', 'old.reddit.com']);
    expect(items, hasLength(1));
  });

  test('retries the fallback host on a rate limit too', () async {
    final hosts = <String>[];
    final client = MockClient((req) async {
      hosts.add(req.url.host);
      if (req.url.host == 'www.reddit.com') {
        return http.Response('slow down', 429);
      }
      return http.Response(listingJson(), 200);
    });

    await fetch(client);
    expect(hosts, hasLength(2));
  });

  test('does not retry a 404, which means the same everywhere', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('not found', 404);
    });

    expect(
      fetch(client, redditSource('nosuchsub')),
      throwsA(predicate((e) =>
          e is SourceFetchException &&
          e.message.contains('No subreddit called r/nosuchsub'))),
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
  });

  test('explains what a 403 usually means instead of echoing the code',
      () async {
    final client = MockClient((_) async => http.Response('blocked', 403));

    expect(
      fetch(client, redditSource('private')),
      throwsA(predicate((e) =>
          e is SourceFetchException &&
          e.message.contains('private') &&
          e.message.contains('quarantined'))),
    );
  });

  test('explains a rate limit in plain language', () async {
    final client = MockClient((_) async => http.Response('slow down', 429));

    expect(
      fetch(client),
      throwsA(predicate((e) =>
          e is SourceFetchException &&
          e.message.contains('rate limiting'))),
    );
  });
}
