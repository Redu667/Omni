import 'package:flutter_test/flutter_test.dart';
import 'package:omni/models/feed_item.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/post_search.dart';

FeedItem post({
  String id = '1',
  String author = 'Someone',
  String? handle,
  String? title,
  String text = '',
  String? fullText,
  String? flair,
  String? context,
  List<MediaItem> media = const [],
  FeedItem? quoted,
  LinkCard? linkCard,
}) =>
    FeedItem(
      id: id,
      sourceId: 's',
      network: Network.mastodon,
      author: author,
      handle: handle,
      createdAt: DateTime.utc(2026, 1, 1),
      title: title,
      text: text,
      fullText: fullText,
      flair: flair,
      context: context,
      media: media,
      quoted: quoted,
      linkCard: linkCard,
    );

void main() {
  group('searchTerms', () {
    test('splits on whitespace and lowercases', () {
      expect(searchTerms('  Flutter   Release '), ['flutter', 'release']);
    });

    test('an empty or blank query yields no terms', () {
      expect(searchTerms(''), isEmpty);
      expect(searchTerms('   '), isEmpty);
    });
  });

  group('postMatches', () {
    test('every term must be present, not just one', () {
      final item = post(text: 'the flutter release is out');
      expect(postMatches(item, ['flutter', 'release']), isTrue);
      expect(postMatches(item, ['flutter', 'kotlin']), isFalse);
    });

    test('matches regardless of case', () {
      expect(postMatches(post(text: 'Shipping OMNI today'), ['omni']), isTrue);
    });

    test('matches partial words, so "rele" finds "release"', () {
      expect(postMatches(post(text: 'release day'), ['rele']), isTrue);
    });

    test('no terms matches nothing', () {
      expect(postMatches(post(text: 'anything'), []), isFalse);
    });
  });

  group('searchableText covers', () {
    test('title, author, handle, context and flair', () {
      final item = post(
        title: 'Headline here',
        author: 'Ada',
        handle: '@ada@example.social',
        context: 'r/law',
        flair: 'Discussion',
      );
      for (final term in ['headline', 'ada', 'example.social', 'law', 'discussion']) {
        expect(postMatches(item, [term]), isTrue, reason: term);
      }
    });

    test('the full body, not only the truncated text', () {
      final item = post(text: 'a summary…', fullText: 'the buried detail');
      expect(postMatches(item, ['buried']), isTrue);
    });

    test('the quoted post, which is often the actual subject', () {
      final item = post(
        text: 'this',
        quoted: post(id: '2', author: 'Grace', text: 'the original claim'),
      );
      expect(postMatches(item, ['original']), isTrue);
      expect(postMatches(item, ['grace']), isTrue);
    });

    test('link card title and description', () {
      final item = post(
        linkCard: LinkCard(
          url: 'https://example.com/a',
          title: 'Annual report',
          description: 'Numbers for the year',
        ),
      );
      expect(postMatches(item, ['annual']), isTrue);
      expect(postMatches(item, ['numbers']), isTrue);
    });

    test('alt text, since it describes what the post is showing', () {
      final item = post(
        media: [MediaItem(url: 'https://e/1.png', alt: 'a red bicycle')],
      );
      expect(postMatches(item, ['bicycle']), isTrue);
    });

    test('non-Latin text', () {
      expect(postMatches(post(text: 'こんにちは 世界'), ['世界']), isTrue);
    });
  });

  group('searchPosts', () {
    final items = [
      post(id: '1', text: 'flutter release notes'),
      post(id: '2', text: 'kotlin release notes'),
      post(id: '3', text: 'unrelated'),
    ];

    test('returns only matches, in the order given', () {
      final results = searchPosts(items, 'release');
      expect(results.map((i) => i.id), ['1', '2']);
    });

    test('narrows as terms are added', () {
      expect(searchPosts(items, 'release flutter').map((i) => i.id), ['1']);
    });

    test('an empty query returns nothing rather than everything', () {
      expect(searchPosts(items, ''), isEmpty);
      expect(searchPosts(items, '   '), isEmpty);
    });
  });
}
