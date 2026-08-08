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

String atomFeed() => '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>law</title>
  <entry>
    <author><name>/u/lawyer</name></author>
    <id>t3_abc</id>
    <link href="https://www.reddit.com/r/law/comments/abc/a_case/" />
    <title>A case worth reading</title>
    <updated>2026-08-06T12:00:00+00:00</updated>
    <content type="html">&lt;img src="https://preview.redd.it/x.png"&gt;</content>
  </entry>
</feed>''';

/// Reddit's block page: HTTP 200, HTML body, no hint in the status code.
http.Response blockPage() => http.Response(
    '<!doctype html>\n<html><head><title>Blocked</title></head>'
    '<body>whoa there, pardner</body></html>',
    200,
    headers: {'content-type': 'text/html; charset=utf-8'});

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

  test('treats a 200 HTML block page as blocked, not as content', () async {
    // Reddit answers 200 with HTML rather than 403; decoding that as JSON
    // used to throw a raw FormatException at the user.
    final hosts = <String>[];
    final client = MockClient((req) async {
      hosts.add(req.url.host);
      if (req.url.path.endsWith('.rss')) return http.Response(atomFeed(), 200);
      return blockPage();
    });

    final items = await fetch(client, redditSource('law'));

    expect(hosts, ['www.reddit.com', 'old.reddit.com', 'www.reddit.com']);
    expect(items, hasLength(1));
    expect(items.single.title, 'A case worth reading');
    expect(items.single.author, 'u/lawyer');
    expect(items.single.context, 'r/law');
    expect(items.single.url,
        'https://www.reddit.com/r/law/comments/abc/a_case/');
    expect(items.single.imageUrls, ['https://preview.redd.it/x.png']);
  });

  test('treats Reddit\'s error JSON as blocked too', () async {
    final client = MockClient((req) async {
      if (req.url.path.endsWith('.rss')) return http.Response(atomFeed(), 200);
      return http.Response('{"message": "Forbidden", "error": 403}', 200);
    });

    expect(await fetch(client, redditSource('law')), hasLength(1));
  });

  test('falls back to the feed after a real 403 as well', () async {
    final client = MockClient((req) async {
      if (req.url.path.endsWith('.rss')) return http.Response(atomFeed(), 200);
      return http.Response('blocked', 403);
    });

    expect(await fetch(client, redditSource('law')), hasLength(1));
  });

  test('never lets a decode error escape when every route is blocked',
      () async {
    final client = MockClient((_) async => blockPage());

    expect(
      fetch(client, redditSource('law')),
      throwsA(isA<SourceFetchException>()),
    );
  });

  test('an entry-less feed counts as failure, not an empty subreddit',
      () async {
    final client = MockClient((req) async {
      if (req.url.path.endsWith('.rss')) {
        return http.Response(
            '<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom">'
            '<title>blocked</title></feed>',
            200);
      }
      return blockPage();
    });

    expect(
      fetch(client, redditSource('law')),
      throwsA(isA<SourceFetchException>()),
    );
  });
}
