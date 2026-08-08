import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/source_client.dart';

FeedSource sub([String name = 'law']) => FeedSource(
      id: 'r',
      network: Network.reddit,
      displayName: 'r/$name',
      params: {'subreddit': name},
    );

Future<List<dynamic>> fetch(MockClient c) =>
    SourceClient.forSource(sub(), c).fetchLatest();

String feedWith(String extra) => '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/">
  <entry>
    <author><name>/u/lawyer</name></author>
    <id>t3_abc</id>
    <link href="https://www.reddit.com/r/law/comments/abc/x/" />
    <title>A ruling</title>
    <updated>2026-08-06T12:00:00+00:00</updated>
    $extra
  </entry>
</feed>''';

MockClient blockedThen(String feed) => MockClient((req) async {
      if (req.url.path.endsWith('.rss')) return http.Response(feed, 200);
      return http.Response('<html>blocked</html>', 200);
    });

void main() {
  test('uses media:thumbnail, which link posts actually carry', () async {
    final items = await fetch(blockedThen(feedWith(
        '<media:thumbnail url="https://b.thumbs.redditmedia.com/x.jpg"/>')));

    expect(items.single.imageUrls, ['https://b.thumbs.redditmedia.com/x.jpg']);
  });

  test('unescapes &amp; in image URLs, which would otherwise 404', () async {
    final items = await fetch(blockedThen(feedWith(
        '<content type="html">&lt;img src="https://preview.redd.it/a.png?'
        'width=640&amp;amp;crop=smart"&gt;</content>')));

    expect(items.single.imageUrls.single,
        'https://preview.redd.it/a.png?width=640&crop=smart');
  });

  test('prefers the thumbnail over an inline image', () async {
    final items = await fetch(blockedThen(feedWith(
        '<media:thumbnail url="https://b.thumbs.redditmedia.com/thumb.jpg"/>'
        '<content type="html">&lt;img src="https://example.com/inline.png"&gt;</content>')));

    expect(items.single.imageUrls,
        ['https://b.thumbs.redditmedia.com/thumb.jpg']);
  });

  test('ignores Reddit\'s non-URL thumbnail placeholders', () async {
    final items = await fetch(
        blockedThen(feedWith('<media:thumbnail url="self"/>')));

    expect(items.single.imageUrls, isEmpty);
  });

  test('a post with no media simply has none', () async {
    final items = await fetch(blockedThen(feedWith(
        '<content type="html">&lt;p&gt;just text&lt;/p&gt;</content>')));

    expect(items.single.imageUrls, isEmpty);
    expect(items.single.title, 'A ruling');
  });

  test('requests the configured sort', () async {
    final paths = <String>[];
    final client = MockClient((req) async {
      paths.add(req.url.path);
      return http.Response(
          jsonEncode({'data': {'children': []}}), 200);
    });

    await SourceClient.forSource(
      FeedSource(
        id: 'r',
        network: Network.reddit,
        displayName: 'r/law · new',
        params: {'subreddit': 'law', 'sort': 'new'},
      ),
      client,
    ).fetchLatest();

    expect(paths.single, '/r/law/new.json');
  });

  test('defaults to hot when no sort is configured', () async {
    final paths = <String>[];
    final client = MockClient((req) async {
      paths.add(req.url.path);
      return http.Response(jsonEncode({'data': {'children': []}}), 200);
    });

    await fetch(client);
    expect(paths.single, '/r/law/hot.json');
  });

  test('marks over-18 posts sensitive', () async {
    final client = MockClient((_) async => http.Response(
        jsonEncode({
          'data': {
            'children': [
              {
                'data': {
                  'name': 't3_x',
                  'title': 'NSFW thing',
                  'author': 'a',
                  'subreddit': 'law',
                  'permalink': '/r/law/x/',
                  'created_utc': 1785924000,
                  'over_18': true,
                },
              },
            ],
          },
        }),
        200));

    final items = await fetch(client);
    expect(items.single.sensitive, isTrue);
    expect(items.single.needsReveal, isTrue);
  });
}
