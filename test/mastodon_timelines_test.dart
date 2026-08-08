import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/mastodon_client.dart';
import 'package:omni/services/source_client.dart';

FeedSource masto(Map<String, String> params) => FeedSource(
      id: 's',
      network: Network.mastodon,
      displayName: 'Mastodon',
      params: {'instance': 'mastodon.social', ...params},
    );

final _status = {
  'id': '1',
  'created_at': '2026-08-05T10:00:00.000Z',
  'content': '<p>hello</p>',
  'account': {'display_name': 'A', 'acct': 'a', 'username': 'a'},
  'media_attachments': [],
};

({List<Uri> seen, List<String?> auth, http.Client client}) recorder(
    Object body,
    {int status = 200}) {
  final seen = <Uri>[];
  final auth = <String?>[];
  final client = MockClient((req) async {
    seen.add(req.url);
    auth.add(req.headers['Authorization']);
    return http.Response.bytes(utf8.encode(jsonEncode(body)), status);
  });
  return (seen: seen, auth: auth, client: client);
}

void main() {
  group('which timeline', () {
    test('a hashtag uses the tag timeline, with or without a token', () async {
      for (final token in [null, 'tok']) {
        final r = recorder([_status]);
        await SourceClient.forSource(
                masto({
                  'hashtag': 'photography',
                  if (token != null) 'accessToken': token,
                }),
                r.client)
            .fetchLatest();

        expect(r.seen.single.path, '/api/v1/timelines/tag/photography');
        expect(r.auth.single, token == null ? isNull : 'Bearer tok');
      }
    });

    test('a leading # is stripped rather than sent', () async {
      final r = recorder([_status]);
      await SourceClient.forSource(masto({'hashtag': '#art'}), r.client)
          .fetchLatest();

      expect(r.seen.single.path, '/api/v1/timelines/tag/art');
    });

    test('a local hashtag asks only for that instance', () async {
      final r = recorder([_status]);
      await SourceClient.forSource(
              masto({'hashtag': 'art', 'local': 'true'}), r.client)
          .fetchLatest();

      expect(r.seen.single.queryParameters['local'], 'true');
    });

    test('a list uses the list timeline with the token', () async {
      final r = recorder([_status]);
      await SourceClient.forSource(
              masto({'list': '42', 'accessToken': 'tok'}), r.client)
          .fetchLatest();

      expect(r.seen.single.path, '/api/v1/timelines/list/42');
      expect(r.auth.single, 'Bearer tok');
    });

    test('a list without a token says lists are private', () async {
      final r = recorder([_status]);
      await expectLater(
        SourceClient.forSource(masto({'list': '42'}), r.client).fetchLatest(),
        throwsA(isA<SourceFetchException>()
            .having((e) => e.toString(), 'message', contains('sign in'))),
      );
      expect(r.seen, isEmpty);
    });

    test('a hashtag wins over a list, and a list over home', () async {
      final r = recorder([_status]);
      await SourceClient.forSource(
              masto({
                'hashtag': 'art',
                'list': '42',
                'accessToken': 'tok',
              }),
              r.client)
          .fetchLatest();
      expect(r.seen.single.path, '/api/v1/timelines/tag/art');

      final r2 = recorder([_status]);
      await SourceClient.forSource(
              masto({'list': '42', 'accessToken': 'tok'}), r2.client)
          .fetchLatest();
      expect(r2.seen.single.path, '/api/v1/timelines/list/42');
    });

    test('neither still gives home when signed in, public when not', () async {
      final r = recorder([_status]);
      await SourceClient.forSource(masto({'accessToken': 'tok'}), r.client)
          .fetchLatest();
      expect(r.seen.single.path, '/api/v1/timelines/home');

      final r2 = recorder([_status]);
      await SourceClient.forSource(masto({}), r2.client).fetchLatest();
      expect(r2.seen.single.path, '/api/v1/timelines/public');
    });
  });

  group('errors name the likely cause', () {
    test('a missing hashtag reads as a missing hashtag', () async {
      final r = recorder(const [], status: 404);
      await expectLater(
        SourceClient.forSource(masto({'hashtag': 'nope'}), r.client)
            .fetchLatest(),
        throwsA(isA<SourceFetchException>()
            .having((e) => e.toString(), 'message', contains('No such hashtag'))),
      );
    });

    test("someone else's list reads as a permissions problem", () async {
      final r = recorder(const [], status: 403);
      await expectLater(
        SourceClient.forSource(
                masto({'list': '9', 'accessToken': 'tok'}), r.client)
            .fetchLatest(),
        throwsA(isA<SourceFetchException>().having((e) => e.toString(),
            'message', contains('another account'))),
      );
    });

    test('an ordinary failure still reports the status', () async {
      final r = recorder(const [], status: 503);
      await expectLater(
        SourceClient.forSource(masto({}), r.client).fetchLatest(),
        throwsA(isA<SourceFetchException>()
            .having((e) => e.toString(), 'message', contains('503'))),
      );
    });
  });

  group('list discovery', () {
    test('returns the account\'s lists as id to title', () async {
      final r = recorder([
        {'id': '1', 'title': 'Friends'},
        {'id': '2', 'title': 'News'},
      ]);
      final lists = await MastodonClient(
              masto({'accessToken': 'tok'}), r.client)
          .fetchLists();

      expect(lists, {'1': 'Friends', '2': 'News'});
      expect(r.auth.single, 'Bearer tok');
    });

    test('asks for nothing without a token', () async {
      final r = recorder(const []);
      final lists = await MastodonClient(masto({}), r.client).fetchLists();

      expect(lists, isEmpty);
      expect(r.seen, isEmpty);
    });

    test('a failure yields no lists rather than an error', () async {
      final r = recorder(const [], status: 401);
      expect(
          await MastodonClient(masto({'accessToken': 'tok'}), r.client)
              .fetchLists(),
          isEmpty);
    });
  });
}
