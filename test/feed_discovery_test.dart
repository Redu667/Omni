import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/services/feed_discovery.dart';

void main() {
  group('findFeedLinkInHtml', () {
    test('finds RSS link and resolves relative href', () {
      const html = '''
<html><head>
  <link rel="stylesheet" href="/style.css">
  <link rel="alternate" type="application/rss+xml" title="Feed" href="/feed.xml">
</head><body></body></html>''';
      expect(
        findFeedLinkInHtml(html, Uri.parse('https://example.com/blog')),
        'https://example.com/feed.xml',
      );
    });

    test('finds Atom link with attributes in any order', () {
      const html =
          '<link href="https://example.com/atom" type="application/atom+xml" rel="alternate">';
      expect(
        findFeedLinkInHtml(html, Uri.parse('https://example.com/')),
        'https://example.com/atom',
      );
    });

    test('returns null when nothing is advertised', () {
      expect(
        findFeedLinkInHtml('<html><head></head></html>',
            Uri.parse('https://example.com/')),
        isNull,
      );
    });
  });

  group('discoverFeedUrl', () {
    test('fetches page and extracts feed link', () async {
      final client = MockClient((req) async => http.Response(
          '<link rel="alternate" type="application/rss+xml" href="/rss">',
          200));
      expect(
        await discoverFeedUrl(client, 'example.com'),
        'https://example.com/rss',
      );
    });

    test('returns null on fetch failure', () async {
      final client = MockClient((_) async => http.Response('nope', 404));
      expect(await discoverFeedUrl(client, 'https://example.com'), isNull);
    });
  });

  group('parseOpml', () {
    test('extracts feeds, dedupes, and skips folders', () {
      const opml = '''
<?xml version="1.0"?>
<opml version="2.0">
  <head><title>Subscriptions</title></head>
  <body>
    <outline text="Tech" title="Tech">
      <outline type="rss" text="The Verge" title="The Verge"
               xmlUrl="https://www.theverge.com/rss/index.xml"/>
      <outline type="rss" text="Dup" xmlUrl="https://www.theverge.com/rss/index.xml"/>
    </outline>
    <outline type="rss" text="HN" xmlUrl="https://news.ycombinator.com/rss"/>
  </body>
</opml>''';
      final feeds = parseOpml(opml);
      expect(feeds, hasLength(2));
      expect(feeds[0].title, 'The Verge');
      expect(feeds[0].url, 'https://www.theverge.com/rss/index.xml');
      expect(feeds[1].title, 'HN');
    });

    test('throws on non-OPML input', () {
      expect(() => parseOpml('<html></html>'), throwsFormatException);
      expect(() => parseOpml('not xml at all'), throwsFormatException);
    });
  });
}
