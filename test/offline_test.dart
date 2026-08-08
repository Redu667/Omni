import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/feed_repository.dart';
import 'package:omni/services/source_health.dart';

FeedSource redditSource([String id = 'r']) => FeedSource(
      id: id,
      network: Network.reddit,
      displayName: 'r/$id',
      params: const {'subreddit': 'law'},
    );

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
  group('classifying the failure', () {
    test('a dropped connection is the network, not the service', () {
      expect(isConnectivityFailure(const SocketException('no route')), isTrue);
      expect(isConnectivityFailure(TimeoutException('slow')), isTrue);
      expect(
          isConnectivityFailure(
              http.ClientException('Failed host lookup: reddit.com')),
          isTrue);
    });

    test('a refusal is the service, not the network', () {
      expect(isConnectivityFailure(http.ClientException('Bad response')),
          isFalse);
      expect(isConnectivityFailure(Exception('403')), isFalse);
      expect(isConnectivityFailure(const FormatException('bad json')), isFalse);
    });
  });

  group('being offline', () {
    FeedRepository offlineRepo() => FeedRepository(
        httpClient: MockClient(
            (_) async => throw const SocketException('Network unreachable')));

    test('does not count against any source', () async {
      final repo = offlineRepo();
      for (var i = 0; i < 5; i++) {
        await repo.fetchAll([redditSource()]);
      }

      // Five failed refreshes in a tunnel shouldn't push a healthy source
      // into a half-hour backoff.
      expect(repo.healthOf('r').consecutiveFailures, 0);
      expect(repo.healthOf('r').retryDelay, Duration.zero);
    });

    test('is reported once rather than per source', () async {
      final result = await offlineRepo()
          .fetchAll([redditSource('a'), redditSource('b'), redditSource('c')]);

      expect(result.offline, isTrue);
      // Three copies of "no connection" is noise, not information.
      expect(result.errors, isEmpty);
    });

    test('keeps showing what each source last gave', () async {
      var online = true;
      final repo = FeedRepository(httpClient: MockClient((_) async {
        if (!online) throw const SocketException('Network unreachable');
        return http.Response(_listing, 200);
      }));

      expect((await repo.fetchAll([redditSource()])).items, hasLength(1));

      online = false;
      final result = await repo.fetchAll([redditSource()]);
      expect(result.items, hasLength(1));
      expect(result.staleSourceIds, contains('r'));
      expect(result.offline, isTrue);
    });

    test('recovers immediately once the signal comes back', () async {
      var online = false;
      final repo = FeedRepository(httpClient: MockClient((_) async {
        if (!online) throw const SocketException('Network unreachable');
        return http.Response(_listing, 200);
      }));

      for (var i = 0; i < 5; i++) {
        await repo.fetchAll([redditSource()]);
      }
      online = true;
      final result = await repo.fetchAll([redditSource()]);

      // No backoff to wait out, because nothing was ever held against it.
      expect(result.items, hasLength(1));
      expect(result.offline, isFalse);
    });
  });

  group('not offline', () {
    test('one source failing to connect while another answers', () async {
      final repo = FeedRepository(httpClient: MockClient((req) async {
        if (req.url.host.contains('reddit')) return http.Response(_listing, 200);
        throw const SocketException('Network unreachable');
      }));

      final result = await repo.fetchAll([
        redditSource(),
        FeedSource(
            id: 'f',
            network: Network.rss,
            displayName: 'Feed',
            params: const {'url': 'https://example.com/feed'}),
      ]);

      // Something answered, so the connection is plainly up.
      expect(result.offline, isFalse);
      expect(result.items, hasLength(1));
    });

    test('a service refusing is still the service refusing', () async {
      final repo = FeedRepository(
          httpClient: MockClient((_) async => http.Response('blocked', 403)));

      final result = await repo.fetchAll([redditSource()]);

      expect(result.offline, isFalse);
      expect(result.errors, isNotEmpty);
      expect(repo.healthOf('r').consecutiveFailures, 1);
    });

    test('no sources at all is not an outage', () async {
      final repo = FeedRepository(
          httpClient: MockClient((_) async => http.Response('{}', 200)));

      expect((await repo.fetchAll(const [])).offline, isFalse);
    });
  });
}
