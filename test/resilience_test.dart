import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/feed_repository.dart';
import 'package:omni/services/resilient_client.dart';
import 'package:omni/services/source_health.dart';

/// No real waiting in tests, and no jitter randomness either.
ResilientClient fast(http.Client inner, {int maxAttempts = 3}) =>
    ResilientClient(
      inner: inner,
      maxAttempts: maxAttempts,
      baseDelay: Duration.zero,
      random: Random(1),
    );

FeedSource src(Network network, Map<String, String> params, {String id = 's'}) =>
    FeedSource(id: id, network: network, displayName: 'T', params: params);

String mastodonJson(String id) => jsonEncode([
      {
        'id': id,
        'created_at': '2026-08-05T12:00:00.000Z',
        'content': '<p>post $id</p>',
        'account': {'display_name': 'A', 'acct': 'a', 'username': 'a'},
        'media_attachments': [],
      },
    ]);

void main() {
  group('ResilientClient', () {
    test('retries a 503 and returns the eventual success', () async {
      var calls = 0;
      final client = fast(MockClient((_) async {
        calls++;
        return calls < 3
            ? http.Response('unavailable', 503)
            : http.Response('ok', 200);
      }));

      final res = await client.get(Uri.https('example.com', '/'));
      expect(res.statusCode, 200);
      expect(calls, 3);
    });

    test('gives up after the attempt limit and returns the last response',
        () async {
      var calls = 0;
      final client = fast(MockClient((_) async {
        calls++;
        return http.Response('nope', 500);
      }));

      final res = await client.get(Uri.https('example.com', '/'));
      expect(res.statusCode, 500);
      expect(calls, 3);
    });

    test('does not retry a 404, which will never change', () async {
      var calls = 0;
      final client = fast(MockClient((_) async {
        calls++;
        return http.Response('missing', 404);
      }));

      await client.get(Uri.https('example.com', '/'));
      expect(calls, 1);
    });

    test('does not retry a 403, since blocked stays blocked', () async {
      // Reddit and X both mean "blocked" by 403; the clients handle it by
      // falling back elsewhere, and retrying only slows that down.
      var calls = 0;
      final client = fast(MockClient((_) async {
        calls++;
        return http.Response('blocked', 403);
      }));

      await client.get(Uri.https('example.com', '/'));
      expect(calls, 1);
    });

    test('retries a rate limit', () async {
      var calls = 0;
      final client = fast(MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response('slow down', 429)
            : http.Response('ok', 200);
      }));

      expect((await client.get(Uri.https('example.com', '/'))).statusCode, 200);
      expect(calls, 2);
    });

    test('gives up rather than waiting out a long Retry-After', () async {
      var calls = 0;
      final client = ResilientClient(
        inner: MockClient((_) async {
          calls++;
          return http.Response('later', 429, headers: {'retry-after': '600'});
        }),
        maxAttempts: 3,
        baseDelay: Duration.zero,
        maxRetryAfter: const Duration(seconds: 20),
        random: Random(1),
      );

      final res = await client.get(Uri.https('example.com', '/'));
      expect(res.statusCode, 429);
      // Asked to wait ten minutes: return control instead of blocking.
      expect(calls, 1);
    });

    test('honours a short Retry-After', () async {
      var calls = 0;
      final client = ResilientClient(
        inner: MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('wait', 429, headers: {'retry-after': '0'})
              : http.Response('ok', 200);
        }),
        maxAttempts: 3,
        baseDelay: Duration.zero,
        random: Random(1),
      );

      expect((await client.get(Uri.https('example.com', '/'))).statusCode, 200);
      expect(calls, 2);
    });

    test('retries a dropped connection', () async {
      var calls = 0;
      final client = fast(MockClient((_) async {
        calls++;
        if (calls == 1) throw const SocketException('connection reset');
        return http.Response('ok', 200);
      }));

      expect((await client.get(Uri.https('example.com', '/'))).statusCode, 200);
      expect(calls, 2);
    });

    test('rethrows a network error that never recovers', () async {
      final client = fast(MockClient((_) async {
        throw const SocketException('no route to host');
      }));

      expect(client.get(Uri.https('example.com', '/')),
          throwsA(isA<SocketException>()));
    });

    test('replays the body on a retried POST', () async {
      final bodies = <String>[];
      final client = fast(MockClient((req) async {
        bodies.add(req.body);
        return bodies.length == 1
            ? http.Response('retry', 503)
            : http.Response('ok', 200);
      }));

      await client.post(Uri.https('example.com', '/'), body: {'a': 'b'});
      expect(bodies, ['a=b', 'a=b']);
    });
  });

  group('SourceHealth', () {
    test('counts consecutive failures and clears on success', () {
      var health = const SourceHealth();
      expect(health.isFailing, isFalse);

      health = health.failed('boom');
      expect(health.consecutiveFailures, 1);
      expect(health.isFailing, isTrue);
      expect(health.isPersistentlyFailing, isFalse);

      health = health.failed('boom').failed('boom');
      expect(health.isPersistentlyFailing, isTrue);

      health = health.succeeded(DateTime.utc(2026, 8, 8));
      expect(health.isFailing, isFalse);
      expect(health.lastSuccess, DateTime.utc(2026, 8, 8));
    });

    test('remembers the last success through a failure', () {
      final health = const SourceHealth()
          .succeeded(DateTime.utc(2026, 8, 1))
          .failed('down');

      expect(health.lastSuccess, DateTime.utc(2026, 8, 1));
      expect(health.lastError, 'down');
      expect(health.stalenessAt(DateTime.utc(2026, 8, 3)),
          const Duration(days: 2));
    });
  });

  group('graceful degradation', () {
    test('a source that starts failing keeps its previous posts', () async {
      var attempt = 0;
      final client = MockClient((req) async {
        attempt++;
        // Works the first time, blocked after that.
        return attempt == 1
            ? http.Response(mastodonJson('1'), 200)
            : http.Response('blocked', 403);
      });

      final repo = FeedRepository(httpClient: client);
      final sources = [src(Network.mastodon, {'instance': 'mastodon.social'})];

      final first = await repo.fetchAll(sources);
      expect(first.items, hasLength(1));
      expect(first.staleSourceIds, isEmpty);

      final second = await repo.fetchAll(sources);
      // The post is still there rather than the feed emptying out.
      expect(second.items, hasLength(1));
      expect(second.staleSourceIds, {'s'});
      expect(second.errors, isNotEmpty);
      expect(repo.healthOf('s').isFailing, isTrue);
    });

    test('a source that never worked contributes nothing', () async {
      final client = MockClient((_) async => http.Response('blocked', 403));

      final repo = FeedRepository(httpClient: client);
      final result = await repo
          .fetchAll([src(Network.mastodon, {'instance': 'mastodon.social'})]);

      expect(result.items, isEmpty);
      expect(result.staleSourceIds, isEmpty);
      expect(result.errors, hasLength(1));
    });

    test('recovering clears the stale marking', () async {
      var attempt = 0;
      final client = MockClient((_) async {
        attempt++;
        return attempt == 2
            ? http.Response('blocked', 403)
            : http.Response(mastodonJson('$attempt'), 200);
      });

      final repo = FeedRepository(httpClient: client);
      final sources = [src(Network.mastodon, {'instance': 'mastodon.social'})];

      await repo.fetchAll(sources);
      expect((await repo.fetchAll(sources)).staleSourceIds, {'s'});

      final recovered = await repo.fetchAll(sources);
      expect(recovered.staleSourceIds, isEmpty);
      expect(repo.healthOf('s').isFailing, isFalse);
    });

    test('paging does not replay a failing source as older posts', () async {
      var call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) {
          // A full page, so there's a cursor to page with.
          return http.Response(
              jsonEncode([
                for (var i = 0; i < 5; i++)
                  jsonDecode(mastodonJson('m$i'))[0],
              ]),
              200);
        }
        return http.Response('blocked', 403);
      });

      final repo = FeedRepository(httpClient: client);
      final sources = [src(Network.mastodon, {'instance': 'mastodon.social'})];

      final first = await repo.fetchAll(sources, limitPerSource: 5);
      expect(first.cursors, isNotEmpty);

      final more = await repo.fetchAll(sources,
          limitPerSource: 5, cursors: first.cursors);

      // Repeating the previous page as "older" would duplicate every post.
      expect(more.items, isEmpty);
      expect(more.staleSourceIds, isEmpty);
    });
  });
}
