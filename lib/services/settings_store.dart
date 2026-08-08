import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/collection.dart';
import '../models/feed_filters.dart';

/// Small app-level preferences that aren't tied to any one source.
class SettingsStore {
  static const _openInAppKey = 'omni_open_in_app';
  static const _filtersKey = 'omni_feed_filters_v1';
  static const _themeKey = 'omni_theme_mode';
  static const _dynamicColourKey = 'omni_dynamic_colour';
  static const _readKey = 'omni_read_ids';
  static const _hideReadKey = 'omni_hide_read';
  static const _markReadOnScrollKey = 'omni_mark_read_on_scroll';
  static const _collectionsKey = 'omni_collections_v1';

  Future<List<Collection>> loadCollections() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_collectionsKey) ?? const [];
    final out = <Collection>[];
    for (final entry in raw) {
      try {
        out.add(Collection.fromJson(
            (jsonDecode(entry) as Map).cast<String, dynamic>()));
      } catch (_) {
        // Skip anything unreadable rather than losing the rest.
      }
    }
    return out;
  }

  Future<void> saveCollections(List<Collection> collections) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_collectionsKey,
        [for (final c in collections) jsonEncode(c.toJson())]);
  }

  /// Ids of posts already read. Capped, because this grows forever
  /// otherwise and old ids stop mattering once they leave the feed.
  Future<Set<String>> loadReadIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_readKey) ?? const []).toSet();
  }

  Future<void> saveReadIds(Set<String> ids, {int cap = 2000}) async {
    final prefs = await SharedPreferences.getInstance();
    final list = ids.toList();
    await prefs.setStringList(
        _readKey, list.length <= cap ? list : list.sublist(list.length - cap));
  }

  Future<bool> loadHideRead() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hideReadKey) ?? false;
  }

  Future<void> saveHideRead(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hideReadKey, value);
  }

  /// Off by default: silently marking things read is the kind of behaviour
  /// that should be asked for rather than assumed.
  Future<bool> loadMarkReadOnScroll() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_markReadOnScrollKey) ?? false;
  }

  Future<void> saveMarkReadOnScroll(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_markReadOnScrollKey, value);
  }

  Future<bool> loadDynamicColour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dynamicColourKey) ?? true;
  }

  Future<void> saveDynamicColour(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dynamicColourKey, value);
  }

  Future<ThemeMode> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString(_themeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }

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
