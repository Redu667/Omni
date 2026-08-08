import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/feed_repository.dart';
import 'package:omni/services/source_health.dart';

FeedSource redditSource() => FeedSource(
      id: 'r',
      network: Network.reddit,
      displayName: 'r/law',
      params: {'subreddit': 'law'},
    );

/// A listing with one post, so a successful fetch is distinguishable from a
/// held-back one.
final _listing = jsonEncode({
  'data': {
    'children': [
      {
        'data': {
          'name': 't3_1',
          'title': 'a post',
          'author': 'someone',
          'permalink': '/r/law/comments/1/a/',
          'subreddit': 'law',
          'created_utc': 1785924000,
        },
      },
    ],
    'after': null,
  },
});

void main() {
  group('SourceHealth backoff', () {
    test('a healthy source is always due', () {
      const health = SourceHealth();
      expect(health.retryDelay, Duration.zero);
      expect(health.shouldFetchAt(DateTime.utc(2026)), isTrue);
    });

    test('the first couple of failures are treated as blips', () {
      final at = DateTime.utc(2026, 8, 1, 12);
      var health = const SourceHealth().failed('boom', at);
      expect(health.retryDelay, Duration.zero);
      expect(health.shouldFetchAt(at), isTrue);

      health = health.failed('boom', at);
      expect(health.retryDelay, Duration.zero);
    });

    test('repeated failures back off, and stop growing', () {
      var health = const SourceHealth();
      final at = DateTime.utc(2026, 8, 1, 12);
      for (var i = 0; i < 3; i++) {
        health = health.failed('403', at);
      }
      expect(health.retryDelay, const Duration(minutes: 2));

      for (var i = 0; i < 20; i++) {
        health = health.failed('403', at);
      }
      // Capped, so a source is never abandoned outright.
      expect(health.retryDelay, const Duration(minutes: 30));
    });

    test('waiting out the delay makes it due again', () {
      final at = DateTime.utc(2026, 8, 1, 12);
      var health = const SourceHealth();
      for (var i = 0; i < 3; i++) {
        health = health.failed('403', at);
      }

      expect(health.shouldFetchAt(at.add(const Duration(minutes: 1))), isFalse);
      expect(health.shouldFetchAt(at.add(const Duration(minutes: 3))), isTrue);
    });

    test('force overrides the delay', () {
      final at = DateTime.utc(2026, 8, 1, 12);
      var health = const SourceHealth();
      for (var i = 0; i < 5; i++) {
        health = health.failed('403', at);
      }

      expect(health.shouldFetchAt(at, force: true), isTrue);
    });

    test('a success clears the backoff entirely', () {
      final at = DateTime.utc(2026, 8, 1, 12);
      var health = const SourceHealth();
      for (var i = 0; i < 5; i++) {
        health = health.failed('403', at);
      }

      health = health.succeeded(at);
      expect(health.retryDelay, Duration.zero);
      expect(health.shouldFetchAt(at), isTrue);
    });
  });

  group('the repository honours it', () {
    test('stops asking a source that keeps refusing', () async {
      var calls = 0;
      final repo = FeedRepository(httpClient: MockClient((_) async {
        calls++;
        return http.Response('blocked', 403);
      }));

      // Three failures put it into backoff; the fourth refresh shouldn't
      // reach the network at all.
      for (var i = 0; i < 3; i++) {
        await repo.fetchAll([redditSource()]);
      }
      final beforeHeld = calls;
      await repo.fetchAll([redditSource()]);

      expect(calls, beforeHeld);
      expect(repo.healthOf('r').consecutiveFailures, greaterThanOrEqualTo(3));
    });

    test('a forced refresh asks anyway', () async {
      var calls = 0;
      final repo = FeedRepository(httpClient: MockClient((_) async {
        calls++;
        return http.Response('blocked', 403);
      }));

      for (var i = 0; i < 3; i++) {
        await repo.fetchAll([redditSource()]);
      }
      final beforeForce = calls;
      await repo.fetchAll([redditSource()], force: true);

      expect(calls, greaterThan(beforeForce));
    });

    test('a held-back source keeps showing its last posts', () async {
      var fail = false;
      final repo = FeedRepository(httpClient: MockClient((_) async =>
          fail ? http.Response('blocked', 403) : http.Response(_listing, 200)));

      final good = await repo.fetchAll([redditSource()]);
      expect(good.items, hasLength(1));

      fail = true;
      for (var i = 0; i < 4; i++) {
        final result = await repo.fetchAll([redditSource()]);
        // Still there, and still flagged as not freshly fetched.
        expect(result.items, hasLength(1), reason: 'round $i');
        expect(result.staleSourceIds, contains('r'), reason: 'round $i');
      }
    });

    test('a healthy source is never held back', () async {
      var calls = 0;
      final repo = FeedRepository(httpClient: MockClient((_) async {
        calls++;
        return http.Response(_listing, 200);
      }));

      for (var i = 0; i < 5; i++) {
        await repo.fetchAll([redditSource()]);
      }
      expect(calls, 5);
    });
  });
}
