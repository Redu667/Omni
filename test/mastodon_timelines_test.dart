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
  _filterTests();
  _collectionTests();
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

/// Bookmarks and favourites: private, and paged differently from timelines.
void _collectionTests() {
  ({List<Uri> seen, http.Client client}) linkRecorder(String? link) {
    final seen = <Uri>[];
    final client = MockClient((req) async {
      seen.add(req.url);
      return http.Response.bytes(
        utf8.encode(jsonEncode([_status])),
        200,
        headers: {if (link != null) 'link': link},
      );
    });
    return (seen: seen, client: client);
  }

  group('bookmarks and favourites', () {
    test('each uses its own endpoint', () async {
      for (final name in ['bookmarks', 'favourites']) {
        final r = linkRecorder(null);
        await SourceClient.forSource(
                masto({'collection': name, 'accessToken': 'tok'}), r.client)
            .fetchLatest();
        expect(r.seen.single.path, '/api/v1/$name');
      }
    });

    test('without a token, says they are private', () async {
      final r = linkRecorder(null);
      await expectLater(
        SourceClient.forSource(masto({'collection': 'bookmarks'}), r.client)
            .fetchLatest(),
        throwsA(isA<SourceFetchException>()
            .having((e) => e.toString(), 'message', contains('private'))),
      );
      expect(r.seen, isEmpty);
    });

    test('pages from the Link header, not the status id', () async {
      final r = linkRecorder(
          '<https://mastodon.social/api/v1/bookmarks?max_id=99>; rel="next", '
          '<https://mastodon.social/api/v1/bookmarks?min_id=1>; rel="prev"');

      final page = await SourceClient.forSource(
              masto({'collection': 'bookmarks', 'accessToken': 'tok'}),
              r.client)
          .fetchPage();

      // '1' is the status id; '99' is the bookmark id paging actually needs.
      expect(page.nextCursor, '99');
    });

    test('no next link means there is no more', () async {
      final r = linkRecorder(
          '<https://mastodon.social/api/v1/bookmarks?min_id=1>; rel="prev"');
      final page = await SourceClient.forSource(
              masto({'collection': 'bookmarks', 'accessToken': 'tok'}),
              r.client)
          .fetchPage();

      expect(page.nextCursor, isNull);
      expect(page.hasMore, isFalse);
    });

    test('an unknown collection falls through to the home timeline', () async {
      final r = linkRecorder(null);
      await SourceClient.forSource(
              masto({'collection': 'nonsense', 'accessToken': 'tok'}), r.client)
          .fetchLatest();

      expect(r.seen.single.path, '/api/v1/timelines/home');
    });

    test('a malformed Link header is ignored rather than fatal', () {
      expect(MastodonClient.nextMaxId(null), isNull);
      expect(MastodonClient.nextMaxId('garbage'), isNull);
      expect(MastodonClient.nextMaxId('<no-brackets; rel="next"'), isNull);
      expect(MastodonClient.nextMaxId('<https://x/a>; rel="next"'), isNull);
    });
  });
}

/// Mastodon evaluates the reader's own filters server-side and reports the
/// verdict on each status.
void _filterTests() {
  Map<String, dynamic> filtered(String action, {String title = 'Politics'}) => {
        'filter': {'id': '1', 'title': title, 'filter_action': action},
        'keyword_matches': ['election'],
      };

  Map<String, dynamic> status({
    List<Map<String, dynamic>>? results,
    Map<String, dynamic>? reblog,
    String? spoiler,
  }) =>
      {
        'id': '1',
        'created_at': '2026-08-05T10:00:00.000Z',
        'content': '<p>hello</p>',
        'account': {'display_name': 'A', 'acct': 'a', 'username': 'a'},
        'media_attachments': [],
        if (spoiler != null) 'spoiler_text': spoiler,
        if (results != null) 'filtered': results,
        if (reblog != null) 'reblog': reblog,
      };

  group("the instance's own filters", () {
    test('a hide filter drops the post entirely', () async {
      final r = recorder([
        status(results: [filtered('hide')]),
        status(),
      ]);
      final items = await SourceClient.forSource(
              masto({'accessToken': 'tok'}), r.client)
          .fetchLatest();

      expect(items, hasLength(1));
    });

    test('a warn filter hides the body behind a reveal, naming the filter',
        () async {
      final r = recorder([
        status(results: [filtered('warn')]),
      ]);
      final item = (await SourceClient.forSource(
                  masto({'accessToken': 'tok'}), r.client)
              .fetchLatest())
          .single;

      expect(item.needsReveal, isTrue);
      expect(item.contentWarning, 'Filtered: Politics');
    });

    test("a filter outranks the author's own warning", () async {
      final r = recorder([
        status(results: [filtered('warn')], spoiler: 'spoilers ahead'),
      ]);
      final item = (await SourceClient.forSource(
                  masto({'accessToken': 'tok'}), r.client)
              .fetchLatest())
          .single;

      expect(item.contentWarning, startsWith('Filtered'));
    });

    test('a boost of something filtered is dropped too', () async {
      final r = recorder([
        status(reblog: status(results: [filtered('hide')])),
      ]);
      final items = await SourceClient.forSource(
              masto({'accessToken': 'tok'}), r.client)
          .fetchLatest();

      expect(items, isEmpty);
    });

    test('an unfiltered post is untouched', () async {
      final r = recorder([status(spoiler: 'spoilers ahead')]);
      final item = (await SourceClient.forSource(
                  masto({'accessToken': 'tok'}), r.client)
              .fetchLatest())
          .single;

      expect(item.contentWarning, 'spoilers ahead');
    });

    test('an empty or absent filtered list changes nothing', () async {
      final r = recorder([status(results: const [])]);
      final item = (await SourceClient.forSource(
                  masto({'accessToken': 'tok'}), r.client)
              .fetchLatest())
          .single;

      expect(item.needsReveal, isFalse);
      expect(MastodonClient.isFilteredOut(null), isFalse);
      expect(MastodonClient.isFilteredOut('nonsense'), isFalse);
    });

    test('a filter with no title still says something', () async {
      final r = recorder([
        status(results: [filtered('warn', title: '')]),
      ]);
      final item = (await SourceClient.forSource(
                  masto({'accessToken': 'tok'}), r.client)
              .fetchLatest())
          .single;

      expect(item.contentWarning, 'Filtered');
    });
  });
}
