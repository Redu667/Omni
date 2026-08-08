import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/source_client.dart';

FeedSource bsky(Map<String, String> params) => FeedSource(
    id: 's', network: Network.bluesky, displayName: 'Feed', params: params);

const _onePost = {
  'feed': [
    {
      'post': {
        'uri': 'at://did:plc:a/app.bsky.feed.post/1',
        'cid': 'c1',
        'author': {'handle': 'a.bsky.social', 'displayName': 'A'},
        'record': {'text': 'hello', 'createdAt': '2026-08-05T10:00:00.000Z'},
      },
    },
  ],
  'cursor': 'next',
};

/// Records every URL the client asks for, answering each with a canned body.
({List<Uri> seen, http.Client client}) recorder(
    Map<String, Object> responses) {
  final seen = <Uri>[];
  final client = MockClient((req) async {
    seen.add(req.url);
    for (final entry in responses.entries) {
      if (req.url.path.endsWith(entry.key)) {
        final value = entry.value;
        if (value is int) return http.Response('blocked', value);
        return http.Response.bytes(utf8.encode(jsonEncode(value)), 200);
      }
    }
    return http.Response('unexpected ${req.url}', 404);
  });
  return (seen: seen, client: client);
}

void main() {
  group('custom feeds', () {
    test('an at:// URI is used as-is, via getFeed', () async {
      final r = recorder({'getFeed': _onePost});
      final items = await SourceClient.forSource(
              bsky({'feed': 'at://did:plc:x/app.bsky.feed.generator/hot'}),
              r.client)
          .fetchLatest();

      expect(items, hasLength(1));
      expect(r.seen.single.path, endsWith('app.bsky.feed.getFeed'));
      expect(r.seen.single.queryParameters['feed'],
          'at://did:plc:x/app.bsky.feed.generator/hot');
      // Anonymous requests go to the public AppView.
      expect(r.seen.single.host, 'public.api.bsky.app');
    });

    test('a bsky.app link resolves the handle to a DID first', () async {
      final r = recorder({
        'resolveHandle': {'did': 'did:plc:resolved'},
        'getFeed': _onePost,
      });
      await SourceClient.forSource(
              bsky({
                'feed': 'https://bsky.app/profile/maker.bsky.social/feed/whats-hot'
              }),
              r.client)
          .fetchLatest();

      expect(r.seen.first.path, endsWith('com.atproto.identity.resolveHandle'));
      expect(r.seen.first.queryParameters['handle'], 'maker.bsky.social');
      expect(r.seen.last.queryParameters['feed'],
          'at://did:plc:resolved/app.bsky.feed.generator/whats-hot');
    });

    test('a DID in the link needs no resolution', () async {
      final r = recorder({'getFeed': _onePost});
      await SourceClient.forSource(
              bsky({'feed': 'https://bsky.app/profile/did:plc:abc/feed/news'}),
              r.client)
          .fetchLatest();

      expect(r.seen, hasLength(1));
      expect(r.seen.single.queryParameters['feed'],
          'at://did:plc:abc/app.bsky.feed.generator/news');
    });

    test('a list link uses getListFeed with a list parameter', () async {
      final r = recorder({'getListFeed': _onePost});
      await SourceClient.forSource(
              bsky({'feed': 'https://bsky.app/profile/did:plc:abc/lists/3kabc'}),
              r.client)
          .fetchLatest();

      expect(r.seen.single.path, endsWith('app.bsky.feed.getListFeed'));
      expect(r.seen.single.queryParameters['list'],
          'at://did:plc:abc/app.bsky.graph.list/3kabc');
      expect(r.seen.single.queryParameters, isNot(contains('feed')));
    });

    test('signing in routes the feed through the authenticated host',
        () async {
      final r = recorder({
        'createSession': {'accessJwt': 'jwt'},
        'getFeed': _onePost,
      });
      await SourceClient.forSource(
              bsky({
                'feed': 'at://did:plc:x/app.bsky.feed.generator/hot',
                'identifier': 'me.bsky.social',
                'appPassword': 'abcd-efgh',
              }),
              r.client)
          .fetchLatest();

      expect(r.seen.last.host, 'bsky.social');
      expect(r.seen.last.path, endsWith('app.bsky.feed.getFeed'));
    });

    test('a link that is not a feed says so rather than failing at fetch',
        () async {
      final r = recorder({'getFeed': _onePost});
      await expectLater(
        SourceClient.forSource(
                bsky({'feed': 'https://bsky.app/profile/someone.bsky.social'}),
                r.client)
            .fetchLatest(),
        throwsA(isA<SourceFetchException>()
            .having((e) => e.toString(), 'message', contains('at://'))),
      );
    });

    test('a feed that requires sign-in names the fix', () async {
      final r = recorder({'getFeed': 403});
      await expectLater(
        SourceClient.forSource(
                bsky({'feed': 'at://did:plc:x/app.bsky.feed.generator/hot'}),
                r.client)
            .fetchLatest(),
        throwsA(isA<SourceFetchException>().having(
            (e) => e.toString(), 'message', contains('app password'))),
      );
    });

    test('a plain handle still fetches that author, unchanged', () async {
      final r = recorder({'getAuthorFeed': _onePost});
      final items = await SourceClient.forSource(
              bsky({'handle': '@a.bsky.social'}), r.client)
          .fetchLatest();

      expect(items, hasLength(1));
      expect(r.seen.single.queryParameters['actor'], 'a.bsky.social');
    });
  });
}
