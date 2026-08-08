import 'package:flutter_test/flutter_test.dart';
import 'package:omni/models/feed_item.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/thread_folding.dart';

ThreadEntry reply(String id, int depth) => ThreadEntry(
      depth: depth,
      item: FeedItem(
        id: id,
        sourceId: 's',
        network: Network.reddit,
        author: 'u/someone',
        text: id,
        createdAt: DateTime.utc(2026, 8, 1),
      ),
    );

/// a
///   b
///     c
///   d
/// e
final thread = [
  reply('a', 0),
  reply('b', 1),
  reply('c', 2),
  reply('d', 1),
  reply('e', 0),
];

List<String> idsOf(List<FoldedReply> rows) =>
    [for (final r in rows) r.entry.item.id];

void main() {
  test('nothing collapsed leaves the thread alone', () {
    expect(idsOf(foldThread(thread, {})), ['a', 'b', 'c', 'd', 'e']);
  });

  test('folding a comment hides its whole subtree, not its siblings', () {
    final rows = foldThread(thread, {'a'});
    expect(idsOf(rows), ['a', 'e']);
    expect(rows.first.hidden, 3);
  });

  test('folding mid-thread hides only what is below it', () {
    final rows = foldThread(thread, {'b'});
    expect(idsOf(rows), ['a', 'b', 'd', 'e']);
    expect(rows[1].hidden, 1);
    expect(rows[0].hidden, 0);
  });

  test('folding the last comment still reports what it hid', () {
    final rows = foldThread([reply('x', 0), reply('y', 1)], {'x'});
    expect(idsOf(rows), ['x']);
    expect(rows.single.hidden, 1);
  });

  test('folding a leaf hides nothing and removes nothing', () {
    final rows = foldThread(thread, {'c'});
    expect(idsOf(rows), ['a', 'b', 'c', 'd', 'e']);
    expect(rows[2].hidden, 0);
  });

  test('two folds at different depths both apply', () {
    final rows = foldThread(thread, {'b', 'e'});
    expect(idsOf(rows), ['a', 'b', 'd', 'e']);
  });

  test('a fold inside a fold is simply already hidden', () {
    final rows = foldThread(thread, {'a', 'b'});
    expect(idsOf(rows), ['a', 'e']);
    expect(rows.first.hidden, 3);
  });

  test('collapsing an id that is not in the thread changes nothing', () {
    expect(idsOf(foldThread(thread, {'nope'})), ['a', 'b', 'c', 'd', 'e']);
  });

  test('an empty thread stays empty', () {
    expect(foldThread(const [], {'a'}), isEmpty);
  });
}
