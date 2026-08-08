import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_item.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/source_client.dart';
import 'package:omni/util/text.dart';

/// A distinct id per source, because the RSS client caches parsed items and
/// conditional-request validators statically, keyed by source id.
var _n = 0;
FeedSource feedSource() => FeedSource(
      id: 'rss${_n++}',
      network: Network.rss,
      displayName: 'Feed',
      params: {'url': 'https://example.com/feed.json'},
    );

Future<List<FeedItem>> fetch(String body) => SourceClient.forSource(
      feedSource(),
      MockClient((_) async =>
          http.Response.bytes(utf8.encode(body), 200)),
    ).fetchLatest();

void main() {
  group('JSON Feed', () {
    test('reads title, body, link, author and date', () async {
      final items = await fetch(jsonEncode({
        'version': 'https://jsonfeed.org/version/1.1',
        'title': 'A Blog',
        'items': [
          {
            'id': '1',
            'url': 'https://example.com/a',
            'title': 'A post',
            'content_html': '<p>the body</p>',
            'date_published': '2026-08-05T10:00:00Z',
            'authors': [
              {'name': 'Ada'},
            ],
          },
        ],
      }));

      final item = items.single;
      expect(item.title, 'A post');
      expect(item.text, 'the body');
      expect(item.url, 'https://example.com/a');
      expect(item.author, 'Ada');
      expect(item.context, 'A Blog');
      expect(item.createdAt, DateTime.utc(2026, 8, 5, 10));
    });

    test('prefers content_text when the feed gives both', () async {
      final items = await fetch(jsonEncode({
        'version': 'https://jsonfeed.org/version/1.1',
        'items': [
          {
            'id': '1',
            'content_text': 'plain words',
            'content_html': '<p>marked up</p>',
          },
        ],
      }));

      expect(items.single.text, 'plain words');
    });

    test('falls back to the feed title when an item has no author', () async {
      final items = await fetch(jsonEncode({
        'title': 'A Blog',
        'items': [
          {'id': '1', 'content_text': 'x'},
        ],
      }));

      expect(items.single.author, 'A Blog');
    });

    test('carries an item image and its attachments', () async {
      final items = await fetch(jsonEncode({
        'title': 'A Podcast',
        'items': [
          {
            'id': '1',
            'image': 'https://example.com/cover.png',
            'content_text': 'episode 1',
            'attachments': [
              {
                'url': 'https://example.com/ep1.mp3',
                'mime_type': 'audio/mpeg',
              },
              {
                'url': 'https://example.com/notes.pdf',
                'mime_type': 'application/pdf',
              },
            ],
          },
        ],
      }));

      final media = items.single.media;
      // The PDF has no way to be presented, so it isn't pretended into one.
      expect(media, hasLength(2));
      expect(media.first.kind, MediaKind.image);
      expect(media.last.kind, MediaKind.audio);
      expect(media.last.thumbnailUrl, 'https://example.com/cover.png');
    });

    test('JSON that is not a feed reports a bad feed, not a crash', () async {
      await expectLater(
        fetch(jsonEncode({'hello': 'world'})),
        throwsA(isA<SourceFetchException>()
            .having((e) => e.toString(), 'message', contains('not a valid'))),
      );
    });

    test('XML feeds are unaffected by the JSON path', () async {
      final items = await fetch('''<?xml version="1.0"?>
<rss version="2.0"><channel>
  <title>An XML Blog</title>
  <item>
    <title>Still works</title>
    <link>https://example.com/x</link>
    <description>hi</description>
  </item>
</channel></rss>''');

      expect(items.single.title, 'Still works');
    });
  });

  group('RSS enclosures', () {
    Future<List<FeedItem>> rss(String itemXml) => fetch('''<?xml version="1.0"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
<channel>
  <title>A Show</title>
  <itunes:image href="https://example.com/show.png"/>
  $itemXml
</channel></rss>''');

    test('a podcast episode becomes playable audio with its duration',
        () async {
      final items = await rss('''
  <item>
    <title>Episode 1</title>
    <link>https://example.com/1</link>
    <itunes:duration>01:02:03</itunes:duration>
    <enclosure url="https://example.com/1.mp3" type="audio/mpeg" length="1"/>
  </item>''');

      final media = items.single.media.single;
      expect(media.kind, MediaKind.audio);
      expect(media.url, 'https://example.com/1.mp3');
      expect(media.durationSeconds, 3723);
      // No episode art, so the show's stands in.
      expect(media.thumbnailUrl, 'https://example.com/show.png');
    });

    test('episode art wins over the show art', () async {
      final items = await rss('''
  <item>
    <title>Episode 2</title>
    <itunes:image href="https://example.com/ep2.png"/>
    <enclosure url="https://example.com/2.mp3" type="audio/mpeg"/>
  </item>''');

      expect(items.single.media.single.thumbnailUrl,
          'https://example.com/ep2.png');
    });

    test('a video enclosure is a video', () async {
      final items = await rss('''
  <item>
    <title>A clip</title>
    <enclosure url="https://example.com/c.mp4" type="video/mp4"/>
  </item>''');

      expect(items.single.media.single.kind, MediaKind.video);
    });

    test('an image enclosure still works, without a thumbnail of its own',
        () async {
      final items = await rss('''
  <item>
    <title>A picture</title>
    <enclosure url="https://example.com/p.jpg" type="image/jpeg"/>
  </item>''');

      expect(items.single.media.single.kind, MediaKind.image);
      expect(items.single.media.single.thumbnailUrl, isNull);
    });

    test('an enclosure Omni cannot present is skipped', () async {
      final items = await rss('''
  <item>
    <title>A document</title>
    <enclosure url="https://example.com/d.pdf" type="application/pdf"/>
  </item>''');

      expect(items.single.media, isEmpty);
    });
  });

  group('parseDurationSeconds', () {
    test('reads plain seconds', () => expect(parseDurationSeconds('90'), 90));
    test('reads mm:ss', () => expect(parseDurationSeconds('2:30'), 150));
    test('reads hh:mm:ss', () => expect(parseDurationSeconds('1:00:00'), 3600));
    test('ignores nonsense', () {
      expect(parseDurationSeconds(null), isNull);
      expect(parseDurationSeconds(''), isNull);
      expect(parseDurationSeconds('soon'), isNull);
      expect(parseDurationSeconds('1:xx'), isNull);
    });
  });
}
