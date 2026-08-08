import 'package:flutter_test/flutter_test.dart';
import 'package:omni/models/feed_item.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/feed_discovery.dart';

FeedItem sample({String id = 'x'}) => FeedItem(
      id: id,
      sourceId: 's1',
      network: Network.bluesky,
      author: 'Alice',
      handle: '@alice.bsky.social',
      avatarUrl: 'https://cdn/a.jpg',
      title: 'A title',
      text: 'body text',
      fullText: 'the longer body text',
      url: 'https://bsky.app/profile/alice.bsky.social/post/1',
      nativeId: 'at://did/app.bsky.feed.post/1',
      media: const [
        MediaItem(url: 'https://cdn/1.jpg', alt: 'a cat'),
        MediaItem(url: 'https://cdn/2.jpg'),
      ],
      repostedBy: 'Bob',
      likes: 5,
      reposts: 2,
      replies: 1,
      context: 'Bluesky home',
      contentWarning: 'spoilers',
      sensitive: true,
      createdAt: DateTime.utc(2026, 8, 5, 12, 30),
    );

void main() {
  group('FeedItem serialization', () {
    test('round-trips every field a saved post needs', () {
      final restored = FeedItem.fromJson(sample().toJson());

      expect(restored.id, 'x');
      expect(restored.network, Network.bluesky);
      expect(restored.author, 'Alice');
      expect(restored.handle, '@alice.bsky.social');
      expect(restored.title, 'A title');
      expect(restored.text, 'body text');
      expect(restored.fullText, 'the longer body text');
      expect(restored.imageUrls, ['https://cdn/1.jpg', 'https://cdn/2.jpg']);
      expect(restored.media.first.alt, 'a cat');
      expect(restored.media.first.hasAlt, isTrue);
      expect(restored.media.last.hasAlt, isFalse);
      expect(restored.repostedBy, 'Bob');
      expect(restored.likes, 5);
      expect(restored.nativeId, 'at://did/app.bsky.feed.post/1');
      expect(restored.contentWarning, 'spoilers');
      expect(restored.sensitive, isTrue);
      expect(restored.createdAt, DateTime.utc(2026, 8, 5, 12, 30));
    });

    test('a warning survives so it is not lost on reload', () {
      // Reloading a saved post must not quietly strip its content warning.
      final restored = FeedItem.fromJson(sample().toJson());
      expect(restored.needsReveal, isTrue);
    });

    test('reads media from posts saved before alt text existed', () {
      // Older saves stored bare URLs under imageUrls.
      final restored = FeedItem.fromJson({
        'id': 'legacy',
        'network': 'reddit',
        'author': 'a',
        'createdAt': '2026-08-05T00:00:00Z',
        'imageUrls': ['https://cdn/old.jpg'],
      });
      expect(restored.imageUrls, ['https://cdn/old.jpg']);
      expect(restored.media.single.hasAlt, isFalse);
    });

    test('tolerates a minimal payload', () {
      final restored = FeedItem.fromJson({
        'id': 'y',
        'network': 'rss',
        'author': 'Feed',
        'createdAt': '2026-08-05T00:00:00Z',
      });
      expect(restored.sourceId, '');
      expect(restored.imageUrls, isEmpty);
      expect(restored.sensitive, isFalse);
      expect(restored.needsReveal, isFalse);
    });

    test('falls back to now when the date is unreadable', () {
      final restored = FeedItem.fromJson({
        'id': 'z',
        'network': 'rss',
        'author': 'Feed',
        'createdAt': 'not a date',
      });
      expect(restored.createdAt.isUtc, isTrue);
    });
  });

  group('OPML export', () {
    test('produces a document its own parser accepts', () {
      const feeds = [
        OpmlFeed(title: 'The Verge', url: 'https://theverge.com/rss'),
        OpmlFeed(title: 'Hacker News', url: 'https://news.ycombinator.com/rss'),
      ];

      final parsed = parseOpml(buildOpml(feeds));

      expect(parsed, hasLength(2));
      expect(parsed[0].title, 'The Verge');
      expect(parsed[0].url, 'https://theverge.com/rss');
      expect(parsed[1].title, 'Hacker News');
    });

    test('escapes characters that would break the XML', () {
      const feeds = [
        OpmlFeed(title: 'Tom & Jerry <news>', url: 'https://x.com/f?a=1&b=2'),
      ];

      final xml = buildOpml(feeds);
      expect(xml, contains('&amp;'));
      expect(xml, isNot(contains('<news>')));

      // The real test is that it survives a round-trip intact.
      final parsed = parseOpml(xml);
      expect(parsed.single.title, 'Tom & Jerry <news>');
      expect(parsed.single.url, 'https://x.com/f?a=1&b=2');
    });

    test('an empty export is still valid OPML', () {
      expect(parseOpml(buildOpml(const [])), isEmpty);
    });
  });
}
