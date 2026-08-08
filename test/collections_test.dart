import 'package:flutter_test/flutter_test.dart';
import 'package:omni/models/collection.dart';

void main() {
  const collection = Collection(
    id: 'c1',
    name: 'AQW',
    sourceIds: {'reddit-aqw', 'twitter-aqw'},
  );

  test('knows which sources belong to it', () {
    expect(collection.contains('reddit-aqw'), isTrue);
    expect(collection.contains('mastodon-art'), isFalse);
  });

  test('adding a source leaves the others alone', () {
    final updated = collection.withSource('bluesky-aqw', true);
    expect(updated.sourceIds,
        {'reddit-aqw', 'twitter-aqw', 'bluesky-aqw'});
    expect(updated.name, 'AQW');
    expect(updated.id, 'c1');
  });

  test('adding a source already present changes nothing', () {
    expect(collection.withSource('reddit-aqw', true).sourceIds,
        collection.sourceIds);
  });

  test('removing a source drops only that one', () {
    expect(collection.withSource('reddit-aqw', false).sourceIds,
        {'twitter-aqw'});
  });

  test('removing a source that was never in it is harmless', () {
    expect(collection.withSource('nothing', false).sourceIds,
        collection.sourceIds);
  });

  test('renaming keeps membership', () {
    final renamed = collection.copyWith(name: 'AdventureQuest');
    expect(renamed.name, 'AdventureQuest');
    expect(renamed.sourceIds, collection.sourceIds);
  });

  test('round-trips through JSON', () {
    final restored = Collection.fromJson(collection.toJson());
    expect(restored.id, 'c1');
    expect(restored.name, 'AQW');
    expect(restored.sourceIds, {'reddit-aqw', 'twitter-aqw'});
  });

  test('survives a payload missing its name', () {
    final restored = Collection.fromJson({'id': 'c2'});
    expect(restored.name, 'Untitled');
    expect(restored.sourceIds, isEmpty);
  });

  test('an empty collection contains nothing', () {
    const empty = Collection(id: 'c3', name: 'New');
    expect(empty.contains('anything'), isFalse);
    expect(empty.sourceIds, isEmpty);
  });
}
