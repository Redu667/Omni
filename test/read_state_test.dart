import 'package:flutter_test/flutter_test.dart';
import 'package:omni/models/feed_item.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/feed_cache.dart';
import 'package:omni/services/reddit_auth.dart';
import 'package:omni/services/saved_store.dart';
import 'package:omni/services/settings_store.dart';
import 'package:omni/services/source_store.dart';
import 'package:omni/services/twitter_guest_config.dart';
import 'package:omni/services/twitter_session_store.dart';
import 'package:omni/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// No configured sources, so [AppState.init] shows the cache and stops
/// rather than reaching for the network.
class _NoSources extends SourceStore {
  @override
  Future<List<FeedSource>> load() async => const [];
}

class _CachedTimeline extends FeedCache {
  _CachedTimeline(this.items);
  final List<FeedItem> items;

  @override
  Future<List<FeedItem>> load() async => items;

  @override
  Future<void> save(List<FeedItem> items) async {}
}

class _NoSaved extends SavedStore {
  @override
  Future<List<FeedItem>> load() async => const [];
}

/// Credentials live in platform secure storage, which isn't there in a unit
/// test — these stand in so [AppState.init] can complete.
class _NoRedditCredentials extends RedditCredentialStore {
  @override
  Future<String?> loadClientId() async => null;
}

class _NoTwitterConfig extends TwitterGuestConfigStore {
  @override
  Future<TwitterGuestConfig> load() async => TwitterGuestConfig.defaults;
}

class _NoTwitterSession extends TwitterSessionStore {
  @override
  Future<TwitterSession?> load() async => null;
}

FeedItem post(String id) => FeedItem(
      id: id,
      sourceId: 's',
      network: Network.rss,
      author: 'someone',
      text: 'post $id',
      createdAt: DateTime.utc(2026, 8, 1),
    );

Future<AppState> stateWith(List<FeedItem> items) async {
  final state = AppState(
    store: _NoSources(),
    cache: _CachedTimeline(items),
    savedStore: _NoSaved(),
    settingsStore: SettingsStore(),
    redditCredentials: _NoRedditCredentials(),
    twitterConfigStore: _NoTwitterConfig(),
    twitterSessionStore: _NoTwitterSession(),
  );
  await state.init();
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('marking read by scrolling dims posts without moving them', () async {
    final state = await stateWith([post('1'), post('2'), post('3')]);
    await state.setHideRead(true);

    await state.markScrolledRead(['1', '2']);

    expect(state.isRead(post('1')), isTrue);
    expect(state.isRead(post('2')), isTrue);
    // Still on screen: pulling them out from under the scroll position is
    // the whole thing this avoids.
    expect(state.items.map((i) => i.id), ['1', '2', '3']);
    expect(state.unreadCount, 1);
  });

  test('opening a post still hides it immediately', () async {
    final state = await stateWith([post('1'), post('2')]);
    await state.setHideRead(true);

    await state.markRead(post('1'));

    expect(state.items.map((i) => i.id), ['2']);
  });

  test('with hide-read off, scrolled-past posts simply stay', () async {
    final state = await stateWith([post('1'), post('2')]);

    await state.markScrolledRead(['1']);

    expect(state.items.map((i) => i.id), ['1', '2']);
    expect(state.isRead(post('1')), isTrue);
  });

  test('the setting is off unless asked for, and persists', () async {
    final state = await stateWith([post('1')]);
    expect(state.markReadOnScroll, isFalse);

    await state.setMarkReadOnScroll(true);
    expect(state.markReadOnScroll, isTrue);
    expect(await SettingsStore().loadMarkReadOnScroll(), isTrue);
  });

  test('read ids survive being marked twice', () async {
    final state = await stateWith([post('1'), post('2')]);

    await state.markScrolledRead(['1']);
    await state.markScrolledRead(['1', '2']);

    expect(state.unreadCount, 0);
    expect(await SettingsStore().loadReadIds(), {'1', '2'});
  });
}
