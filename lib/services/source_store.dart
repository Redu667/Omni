import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/feed_source.dart';

/// Persists the configured sources.
///
/// The whole list lives in encrypted storage because source configs can
/// contain access tokens and app passwords.
class SourceStore {
  SourceStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  static const _key = 'omni_sources_v1';
  final FlutterSecureStorage _storage;

  Future<List<FeedSource>> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => FeedSource.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<FeedSource> sources) => _storage.write(
      key: _key,
      value: jsonEncode(sources.map((s) => s.toJson()).toList()));
}
