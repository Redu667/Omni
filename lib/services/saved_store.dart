import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/feed_item.dart';

/// Posts the user kept.
///
/// The whole post is stored, not a reference, so a saved post survives its
/// source being removed, the network going down, or the post being deleted
/// upstream — which is most of the point of saving it.
class SavedStore {
  static const _key = 'omni_saved_posts_v1';

  Future<List<FeedItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key);
    if (raw == null) return [];

    final items = <FeedItem>[];
    for (final entry in raw) {
      try {
        items.add(FeedItem.fromJson(
            (jsonDecode(entry) as Map).cast<String, dynamic>()));
      } catch (_) {
        // One unreadable entry shouldn't cost the user the rest.
      }
    }
    return items;
  }

  Future<void> save(List<FeedItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, [for (final item in items) jsonEncode(item.toJson())]);
  }
}
