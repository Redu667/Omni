import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';

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
/// The alarm is inexact and doesn't wake the device: Android is free to
/// batch it with other work and defer it, which for a feed is the right
/// trade. The interval is a request, not a promise.
///
/// This uses AlarmManager rather than WorkManager, which would otherwise be
/// the obvious choice — see the note on [BackgroundRefresh].
/// Any stable integer; it only has to be the same one used to cancel.
const backgroundAlarmId = 6461;

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

/// Schedules the periodic fetch, or cancels it when switched off.
///
/// WorkManager would be the conventional choice and gives better battery
/// behaviour, but the `workmanager` package can't be used here: 0.10.x
/// requires a newer Flutter SDK than this project targets, every reachable
/// 0.9.x has a platform implementation that doesn't match its own
/// interface, and 0.5.x still uses Flutter's v1 Android embedding, which
/// the engine removed. AlarmManager is the working alternative.
class BackgroundRefresh {
  const BackgroundRefresh();

  Future<void> enable(Duration interval) async {
    await AndroidAlarmManager.cancel(backgroundAlarmId);
    await AndroidAlarmManager.periodic(
      interval,
      backgroundAlarmId,
      onBackgroundAlarm,
      // Inexact and without a wakeup: a feed refresh is not worth pulling
      // the device out of doze for, and Android batches inexact alarms
      // with other work.
      exact: false,
      wakeup: false,
      // Otherwise a restart silently ends background refresh, and the
      // setting would claim to be on while nothing happened.
      rescheduleOnReboot: true,
    );
  }

  Future<void> disable() => AndroidAlarmManager.cancel(backgroundAlarmId);
}

/// The entry point Android calls, in its own isolate with none of the app's
/// state — so everything it needs is loaded from disk.
@pragma('vm:entry-point')
Future<void> onBackgroundAlarm() async {
  try {
    await runBackgroundRefresh();
  } catch (_) {
    // A failed refresh is not worth retrying off-schedule; the next alarm
    // is soon enough, and retrying would only burn battery.
  }
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
