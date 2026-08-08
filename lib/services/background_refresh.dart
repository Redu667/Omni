import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../models/feed_item.dart';
import '../models/feed_source.dart';
import 'feed_repository.dart';
import 'notifications.dart';
import 'reddit_auth.dart';
import 'settings_store.dart';
import 'source_store.dart';
import 'twitter_guest_config.dart';
import 'twitter_session_store.dart';

/// Fetching while Omni is closed, so a post can be announced rather than
/// waiting to be discovered on the next launch.
///
/// Android will not run this more often than every fifteen minutes and is
/// free to run it less often than asked — the interval is a request, not a
/// promise, and battery optimisation may defer it for hours.
const backgroundTaskName = 'dev.omni.refresh';

/// What one background run decided to announce.
typedef Announcement = ({FeedSource source, int count, String preview});

/// Posts worth telling someone about, given what has already been seen.
///
/// Kept separate from the fetching so the rule can be tested: it's the part
/// with the interesting edge — the first run after a source is switched on
/// must announce nothing, because a backlog of forty posts is not news.
List<Announcement> announcementsFor({
  required List<FeedSource> sources,
  required Map<String, List<FeedItem>> fetched,
  required Set<String> seenIds,
  required Set<String> readIds,
  required Set<String> establishedSourceIds,
}) {
  final out = <Announcement>[];

  for (final source in sources) {
    final items = fetched[source.id];
    if (items == null || items.isEmpty) continue;

    // A source Omni has never fetched in the background has no baseline to
    // compare against, so everything would look new. Record and stay quiet.
    if (!establishedSourceIds.contains(source.id)) continue;

    final fresh = items
        .where((i) => !seenIds.contains(i.id) && !readIds.contains(i.id))
        .toList();
    if (fresh.isEmpty) continue;

    final newest = fresh.first;
    out.add((
      source: source,
      count: fresh.length,
      preview: _previewOf(newest),
    ));
  }
  return out;
}

String _previewOf(FeedItem item) {
  final title = item.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  final text = item.text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty) return item.author;
  return text.length > 120 ? '${text.substring(0, 120)}…' : text;
}

/// Registers the periodic task, or cancels it when switched off.
///
/// Cancelling and re-registering on every change is deliberate: Android
/// keeps the old schedule otherwise, and a stale fifteen-minute task
/// outliving the setting that created it is worse than a missed refresh.
class BackgroundRefresh {
  const BackgroundRefresh();

  Future<void> enable(Duration interval) async {
    await Workmanager().cancelByUniqueName(backgroundTaskName);
    await Workmanager().registerPeriodicTask(
      backgroundTaskName,
      backgroundTaskName,
      frequency: interval,
      constraints: Constraints(
        networkType: NetworkType.connected,
        // Fetching five networks on a nearly flat phone is not worth it.
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  Future<void> disable() =>
      Workmanager().cancelByUniqueName(backgroundTaskName);
}

/// The entry point Android calls. Runs in its own isolate with none of the
/// app's state, so everything it needs is loaded from disk.
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != backgroundTaskName) return true;
    try {
      await runBackgroundRefresh();
    } catch (_) {
      // Returning false asks Android to retry, which for a feed refresh
      // just burns battery — the next scheduled run is soon enough.
    }
    return true;
  });
}

/// One background refresh: fetch the sources that opted in, announce
/// what's new, and remember what was seen.
Future<void> runBackgroundRefresh({
  SourceStore? sourceStore,
  SettingsStore? settingsStore,
  FeedRepository? repository,
  Notifications? notifications,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final sources = sourceStore ?? SourceStore();
  final settings = settingsStore ?? SettingsStore();
  final notifier = notifications ?? Notifications();

  final all = await sources.load();
  final wanted = all.where((s) => s.enabled && s.notify).toList();
  if (wanted.isEmpty) return;

  final repo = repository ?? FeedRepository(redditAuth: RedditAuth());
  final result = await repo.fetchAll(
    wanted,
    limitPerSource: 20,
    twitterConfig: await TwitterGuestConfigStore().load(),
    twitterAccount: await TwitterSessionStore().load(),
  );

  // fetchAll merges everything into one list; announcements are per source.
  final bySource = <String, List<FeedItem>>{};
  for (final item in result.items) {
    (bySource[item.sourceId] ??= []).add(item);
  }

  final seen = await settings.loadSeenIds();
  final established = await settings.loadEstablishedSourceIds();

  final announcements = announcementsFor(
    sources: wanted,
    fetched: bySource,
    seenIds: seen,
    readIds: await settings.loadReadIds(),
    establishedSourceIds: established,
  );

  for (final (index, announcement) in announcements.indexed) {
    await notifier.showNewPosts(
      // Stable per source, so a later run replaces rather than stacks.
      id: announcement.source.id.hashCode & 0x7fffffff,
      sourceName: announcement.source.displayName,
      count: announcement.count,
      preview: announcement.preview,
    );
    // Android drops notifications posted in a tight burst; a handful of
    // sources is not worth pacing beyond this.
    if (index < announcements.length - 1) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  await settings.saveSeenIds({
    ...seen,
    for (final item in result.items) item.id,
  });
  await settings.saveEstablishedSourceIds({
    ...established,
    for (final source in wanted)
      if (bySource.containsKey(source.id)) source.id,
  });
}
