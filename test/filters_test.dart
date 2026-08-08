import 'package:flutter_test/flutter_test.dart';
import 'package:omni/models/feed_filters.dart';
import 'package:omni/models/feed_item.dart';
import 'package:omni/models/network.dart';

FeedItem post({
  String author = 'Someone',
  String? handle,
  String? title,
  String text = '',
  String? fullText,
}) =>
    FeedItem(
      id: 'x',
      sourceId: 's',
      network: Network.mastodon,
      author: author,
      handle: handle,
      title: title,
      text: text,
      fullText: fullText,
      createdAt: DateTime.utc(2026),
    );

void main() {
  group('muted words', () {
    test('matches a whole word, case-insensitively', () {
      const filters = FeedFilters(mutedWords: ['spoiler']);
      expect(filters.hides(post(text: 'Big SPOILER ahead')), isTrue);
      expect(filters.hides(post(text: 'nothing to see')), isFalse);
    });

    test('does not match inside a longer word', () {
      const filters = FeedFilters(mutedWords: ['art']);
      expect(filters.hides(post(text: 'the start of something')), isFalse);
      expect(filters.hides(post(text: 'a piece of art')), isTrue);
    });

    test('treats a multi-word term as a phrase', () {
      const filters = FeedFilters(mutedWords: ['hot take']);
      expect(filters.hides(post(text: 'here is my hot take, folks')), isTrue);
      expect(filters.hides(post(text: 'take it or leave it')), isFalse);
    });

    test('checks the title and the untruncated body too', () {
      const filters = FeedFilters(mutedWords: ['banned']);
      expect(filters.hides(post(title: 'A banned topic')), isTrue);
      expect(
        filters.hides(post(text: 'teaser…', fullText: 'the banned word is here')),
        isTrue,
      );
    });

    test('handles punctuation around the word', () {
      const filters = FeedFilters(mutedWords: ['crypto']);
      expect(filters.hides(post(text: 'thoughts on crypto?')), isTrue);
      expect(filters.hides(post(text: '(crypto) again')), isTrue);
    });
  });

  group('muted accounts', () {
    test('matches regardless of @ or u/ decoration', () {
      const filters = FeedFilters(mutedAccounts: ['spez']);
      expect(filters.hides(post(author: 'u/spez')), isTrue);
      expect(filters.hides(post(author: 'x', handle: '@spez')), isTrue);
      expect(filters.hides(post(author: 'spez')), isTrue);
    });

    test('accepts the decoration in the filter itself', () {
      const filters = FeedFilters(mutedAccounts: ['@someone', 'u/other']);
      expect(filters.hides(post(author: 'someone')), isTrue);
      expect(filters.hides(post(author: 'u/other')), isTrue);
    });

    test('does not match a partial handle', () {
      const filters = FeedFilters(mutedAccounts: ['bob']);
      expect(filters.hides(post(handle: '@bobby')), isFalse);
      expect(filters.hides(post(handle: '@bob')), isTrue);
    });

    test('matches a full fediverse handle exactly', () {
      const filters = FeedFilters(mutedAccounts: ['@user@instance.social']);
      expect(filters.hides(post(handle: '@user@instance.social')), isTrue);
      expect(filters.hides(post(handle: '@user@elsewhere.social')), isFalse);
    });
  });

  group('empty and round-trip', () {
    test('an empty filter set hides nothing', () {
      expect(FeedFilters.empty.isEmpty, isTrue);
      expect(FeedFilters.empty.hides(post(text: 'anything at all')), isFalse);
    });

    test('blank entries are ignored rather than hiding everything', () {
      const filters = FeedFilters(mutedWords: ['  '], mutedAccounts: ['']);
      expect(filters.hides(post(text: 'ordinary post')), isFalse);
    });

    test('survives a JSON round-trip', () {
      const filters =
          FeedFilters(mutedWords: ['one', 'two'], mutedAccounts: ['@a']);
      final restored = FeedFilters.fromJson(filters.toJson());
      expect(restored.mutedWords, ['one', 'two']);
      expect(restored.mutedAccounts, ['@a']);
    });
  });
}
