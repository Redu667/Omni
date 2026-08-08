import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/bluesky_session.dart';
import 'package:omni/services/source_client.dart';

/// Answers each xrpc method by name, recording what was asked.
({List<String> calls, http.Client client}) server({
  Map<String, Object?> session = const {
    'accessJwt': 'access-1',
    'refreshJwt': 'refresh-1',
  },
  Map<String, Object?> refreshed = const {
    'accessJwt': 'access-2',
    'refreshJwt': 'refresh-2',
  },
  int refreshStatus = 200,
  int timelineStatus = 200,
}) {
  final calls = <String>[];
  final client = MockClient((req) async {
    final method = req.url.path.split('.').last;
    calls.add('$method ${req.headers['Authorization'] ?? ''}'.trim());

    if (req.url.path.endsWith('createSession')) {
      return http.Response(jsonEncode(session), 200);
    }
    if (req.url.path.endsWith('refreshSession')) {
      return http.Response(jsonEncode(refreshed), refreshStatus);
    }
    if (timelineStatus != 200) {
      return http.Response('nope', timelineStatus);
    }
    return http.Response.bytes(
        utf8.encode(jsonEncode({'feed': [], 'cursor': null})), 200);
  });
  return (calls: calls, client: client);
}

FeedSource signedIn() => FeedSource(
      id: 's',
      network: Network.bluesky,
      displayName: 'Bluesky',
      params: {'identifier': 'me.bsky.social', 'appPassword': 'abcd-efgh'},
    );

void main() {
  group('token reuse', () {
    test('signs in once and reuses the token across fetches', () async {
      final s = server();
      final sessions = BlueskySessions();

      for (var i = 0; i < 3; i++) {
        await SourceClient.forSource(signedIn(), s.client,
                blueskySessions: sessions)
            .fetchLatest();
      }

      expect(s.calls.where((c) => c.startsWith('createSession')), hasLength(1));
      expect(s.calls.where((c) => c.startsWith('getTimeline')), hasLength(3));
    });

    test('a separate cache signs in separately', () async {
      final s = server();

      await SourceClient.forSource(signedIn(), s.client,
              blueskySessions: BlueskySessions())
          .fetchLatest();
      await SourceClient.forSource(signedIn(), s.client,
              blueskySessions: BlueskySessions())
          .fetchLatest();

      expect(s.calls.where((c) => c.startsWith('createSession')), hasLength(2));
    });

    test('the token is actually sent', () async {
      final s = server();
      await SourceClient.forSource(signedIn(), s.client,
              blueskySessions: BlueskySessions())
          .fetchLatest();

      expect(s.calls.last, 'getTimeline Bearer access-1');
    });
  });

  group('renewal', () {
    test('a rejected token is renewed and the fetch retried', () async {
      // The timeline 401s once, which is what an expired token looks like.
      var timelineCalls = 0;
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add(req.url.path.split('.').last);
        if (req.url.path.endsWith('createSession')) {
          return http.Response(
              jsonEncode({'accessJwt': 'a1', 'refreshJwt': 'r1'}), 200);
        }
        if (req.url.path.endsWith('refreshSession')) {
          return http.Response(
              jsonEncode({'accessJwt': 'a2', 'refreshJwt': 'r2'}), 200);
        }
        timelineCalls++;
        if (timelineCalls == 1) return http.Response('expired', 401);
        return http.Response.bytes(
            utf8.encode(jsonEncode({'feed': [], 'cursor': null})), 200);
      });

      await SourceClient.forSource(signedIn(), client,
              blueskySessions: BlueskySessions())
          .fetchLatest();

      expect(timelineCalls, 2);
      expect(calls, contains('createSession'));
    });

    test('a dead refresh token falls back to signing in', () async {
      final s = server(refreshStatus: 400);
      final sessions = BlueskySessions();

      await SourceClient.forSource(signedIn(), s.client,
              blueskySessions: sessions)
          .fetchLatest();
      sessions.invalidate('me.bsky.social');
      await SourceClient.forSource(signedIn(), s.client,
              blueskySessions: sessions)
          .fetchLatest();

      expect(s.calls.where((c) => c.startsWith('createSession')), hasLength(2));
    });

    test('a refused sign-in surfaces as a readable failure', () async {
      final client = MockClient((req) async =>
          req.url.path.endsWith('createSession')
              ? http.Response('bad password', 401)
              : http.Response('{}', 200));

      await expectLater(
        SourceClient.forSource(signedIn(), client,
                blueskySessions: BlueskySessions())
            .fetchLatest(),
        throwsA(isA<SourceFetchException>().having(
            (e) => e.toString(), 'message', contains('sign-in failed'))),
      );
    });

    test('a 401 with no credentials is reported, not retried forever',
        () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('nope', 401);
      });

      await expectLater(
        SourceClient.forSource(
                FeedSource(
                    id: 's',
                    network: Network.bluesky,
                    displayName: 'Bluesky',
                    params: {'handle': 'a.bsky.social'}),
                client)
            .fetchLatest(),
        throwsA(isA<SourceFetchException>()),
      );
      expect(calls, 1);
    });
  });
}
