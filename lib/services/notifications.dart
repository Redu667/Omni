import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifications for posts that arrived while Omni was closed.
///
/// One notification per source rather than per post: a busy subreddit would
/// otherwise produce forty, which is how someone turns notifications off
/// entirely and stops hearing about the feed they did care about.
class Notifications {
  Notifications([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'omni_new_posts';
  static const _channelName = 'New posts';
  static const _groupKey = 'dev.omni.new_posts';

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } on MissingPluginException {
      // No platform side — a unit test, or a headless run without the
      // plugin registered. Notifications simply don't happen.
      _ready = false;
    }
  }

  /// Android 13+ requires asking. Returns whether Omni may notify.
  Future<bool> requestPermission() async {
    await init();
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return false;
      return await android.requestNotificationsPermission() ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> get allowed async {
    await init();
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Announces [count] new posts from [sourceName], quoting the newest.
  ///
  /// [id] should be stable per source so a later run replaces the earlier
  /// notification rather than stacking a second one beside it.
  Future<void> showNewPosts({
    required int id,
    required String sourceName,
    required int count,
    required String preview,
  }) async {
    await init();
    if (!_ready) return;

    try {
      await _plugin.show(
        id: id,
        title: count == 1 ? sourceName : '$sourceName · $count new posts',
        body: preview,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription:
                'Posts that arrived while Omni was closed, from the sources '
                'you asked to be told about.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            groupKey: _groupKey,
            // A feed update is not an alarm.
            playSound: false,
            enableVibration: false,
          ),
        ),
      );
    } on MissingPluginException {
      // Nothing to do — the run simply produces no notification.
    }
  }

  Future<void> cancelAll() async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } on MissingPluginException {
      // Nothing registered, nothing to cancel.
    }
  }
}
