import 'package:flutter_test/flutter_test.dart';
import 'package:omni/models/feed_item.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/background_refresh.dart';

FeedSource source(String id, {bool notify = true, bool enabled = true}) =>
    FeedSource(
      id: id,
      network: Network.reddit,
      displayName: 'r/$id',
      params: const {'subreddit': 'law'},
      enabled: enabled,
      notify: notify,
    );

FeedItem post(String id, {String sourceId = 'a', String? title, String text = ''}) =>
    FeedItem(
      id: id,
      sourceId: sourceId,
      network: Network.reddit,
      author: 'u/someone',
      title: title,
      text: text,
      createdAt: DateTime.utc(2026, 8, 1),
    );

List<Announcement> announce({
  required List<FeedSource> sources,
  required Map<String, List<FeedItem>> fetched,
  Set<String> seen = const {},
  Set<String> read = const {},
  Set<String> established = const {'a', 'b'},
}) =>
    announcementsFor(
      sources: sources,
      fetched: fetched,
      seenIds: seen,
      readIds: read,
      establishedSourceIds: established,
    );

void main() {
  group('what gets announced', () {
    test('posts never seen before', () {
      final result = announce(
        sources: [source('a')],
        fetched: {
          'a': [post('1', title: 'A headline'), post('2')],
        },
      );

      expect(result.single.count, 2);
      expect(result.single.preview, 'A headline');
    });

    test('nothing, when everything has been seen', () {
      final result = announce(
        sources: [source('a')],
        fetched: {
          'a': [post('1'), post('2')],
        },
        seen: {'1', '2'},
      );

      expect(result, isEmpty);
    });

    test('nothing already read in the app', () {
      final result = announce(
        sources: [source('a')],
        fetched: {
          'a': [post('1'), post('2', title: 'Unread')],
        },
        read: {'1'},
      );

      expect(result.single.count, 1);
      expect(result.single.preview, 'Unread');
    });

    test('one entry per source, not per post', () {
      final result = announce(
        sources: [source('a'), source('b')],
        fetched: {
          'a': [post('1'), post('2')],
          'b': [post('3', sourceId: 'b')],
        },
      );

      // Forty notifications from one busy subreddit is how someone turns
      // notifications off entirely.
      expect(result, hasLength(2));
      expect(result.map((r) => r.count), [2, 1]);
    });
  });

  group('staying quiet', () {
    test('on the first run for a source, whatever it returns', () {
      final result = announce(
        sources: [source('new')],
        fetched: {
          'new': [for (var i = 0; i < 40; i++) post('$i', sourceId: 'new')],
        },
        established: const {},
      );

      // A backlog of forty posts is not news.
      expect(result, isEmpty);
    });

    test('for a source that returned nothing', () {
      expect(announce(sources: [source('a')], fetched: const {'a': []}),
          isEmpty);
    });

    test('for a source that was not fetched at all', () {
      expect(announce(sources: [source('a')], fetched: const {}), isEmpty);
    });
  });

  group('the preview', () {
    test('prefers the title', () {
      final result = announce(
        sources: [source('a')],
        fetched: {
          'a': [post('1', title: 'The headline', text: 'the body')],
        },
      );
      expect(result.single.preview, 'The headline');
    });

    test('falls back to the body, collapsed to one line', () {
      final result = announce(
        sources: [source('a')],
        fetched: {
          'a': [post('1', text: 'first line\n\n  second line')],
        },
      );
      expect(result.single.preview, 'first line second line');
    });

    test('truncates a long body rather than filling the shade', () {
      final result = announce(
        sources: [source('a')],
        fetched: {
          'a': [post('1', text: 'x' * 400)],
        },
      );
      expect(result.single.preview.length, lessThan(130));
      expect(result.single.preview, endsWith('…'));
    });

    test('falls back to the author when there is no text at all', () {
      final result = announce(
        sources: [source('a')],
        fetched: {
          'a': [post('1')],
        },
      );
      expect(result.single.preview, 'u/someone');
    });
  });
}
