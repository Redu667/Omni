import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/feed_item.dart';

/// The last timeline Omni fetched, kept on disk so the app opens with
/// something to read instead of a spinner — and still has a feed with no
/// signal at all.
///
/// A file rather than shared preferences: this is a few hundred KB of JSON,
/// and Android loads all preferences into memory at startup.
class FeedCache {
  FeedCache({this.maxItems = 400});

  /// Enough to fill several screens without the file growing unbounded.
  final int maxItems;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/timeline-cache.json');
  }

  Future<List<FeedItem>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];

      final items = <FeedItem>[];
      for (final entry in decoded) {
        try {
          items.add(FeedItem.fromJson((entry as Map).cast<String, dynamic>()));
        } catch (_) {
          // One bad entry shouldn't cost the whole cache.
        }
      }
      return items;
    } catch (_) {
      // A cache that won't load is a cache miss, never an error.
      return [];
    }
  }

  Future<void> save(List<FeedItem> items) async {
    try {
      final file = await _file();
      final capped = items.take(maxItems).toList();
      await file.writeAsString(
          jsonEncode([for (final item in capped) item.toJson()]));
    } catch (_) {
      // Failing to cache is not worth surfacing; the feed still works.
    }
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Nothing to do — the cache is best-effort by design.
    }
  }
}
