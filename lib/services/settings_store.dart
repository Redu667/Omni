import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/feed_filters.dart';

/// Small app-level preferences that aren't tied to any one source.
class SettingsStore {
  static const _openInAppKey = 'omni_open_in_app';
  static const _filtersKey = 'omni_feed_filters_v1';

  Future<FeedFilters> loadFilters() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_filtersKey);
    if (raw == null || raw.isEmpty) return FeedFilters.empty;
    try {
      return FeedFilters.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return FeedFilters.empty;
    }
  }

  Future<void> saveFilters(FeedFilters filters) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_filtersKey, jsonEncode(filters.toJson()));
  }

  Future<bool> loadOpenInApp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_openInAppKey) ?? true;
  }

  Future<void> saveOpenInApp(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_openInAppKey, value);
  }
}
