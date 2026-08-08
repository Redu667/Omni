import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Application-only OAuth for Reddit.
///
/// Reddit blocks anonymous JSON listings aggressively — even public
/// subreddits routinely answer 403 with an HTML challenge page. An
/// authenticated request doesn't get that treatment, which makes this the
/// actual fix rather than the Atom fallback's damage limitation.
///
/// This is the "installed app" grant: it needs a client ID the user creates
/// at reddit.com/prefs/apps, but no password and no user account, and it
/// grants read-only access to public content.
class RedditAuth {
  RedditAuth({http.Client? httpClient, RedditCredentialStore? store})
      : _http = httpClient ?? http.Client(),
        _store = store ?? RedditCredentialStore();

  final http.Client _http;
  final RedditCredentialStore _store;

  String? _token;
  DateTime? _expiry;

  static const userAgent = 'android:dev.omni:v0.9.0 (unified feed reader)';

  bool get _isFresh =>
      _token != null &&
      _expiry != null &&
      DateTime.now().isBefore(_expiry!.subtract(const Duration(minutes: 2)));

  /// Returns a bearer token, or null when no client ID is configured — in
  /// which case callers fall back to anonymous requests.
  Future<String?> token({bool forceRefresh = false}) async {
    if (!forceRefresh && _isFresh) return _token;

    final clientId = await _store.loadClientId();
    if (clientId == null || clientId.isEmpty) return null;

    // Installed apps authenticate with an empty password.
    final basic = base64Encode(utf8.encode('$clientId:'));
    final res = await _http.post(
      Uri.https('www.reddit.com', '/api/v1/access_token'),
      headers: {
        'Authorization': 'Basic $basic',
        'User-Agent': userAgent,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'grant_type': 'https://oauth.reddit.com/grants/installed_client',
        'device_id': await _store.deviceId(),
      },
    );

    if (res.statusCode != 200) {
      throw RedditAuthException(
          'Reddit rejected the client ID (HTTP ${res.statusCode}). Check it '
          'matches an "installed app" at reddit.com/prefs/apps.');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    _token = body['access_token'] as String?;
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 3600;
    _expiry = DateTime.now().add(Duration(seconds: expiresIn));
    return _token;
  }

  void invalidate() {
    _token = null;
    _expiry = null;
  }
}

class RedditAuthException implements Exception {
  RedditAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class RedditCredentialStore {
  RedditCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _clientIdKey = 'omni_reddit_client_id';
  static const _deviceIdKey = 'omni_reddit_device_id';

  final FlutterSecureStorage _storage;

  Future<String?> loadClientId() async {
    try {
      return await _storage.read(key: _clientIdKey);
    } on MissingPluginException {
      // No platform storage available — treat as "not configured".
      return null;
    }
  }

  Future<void> saveClientId(String? id) => (id == null || id.trim().isEmpty)
      ? _storage.delete(key: _clientIdKey)
      : _storage.write(key: _clientIdKey, value: id.trim());

  /// A stable per-install identifier, which the installed-app grant expects.
  Future<String> deviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;

    // Reddit wants 20-30 characters; the install time plus a counter is
    // stable, unique enough, and carries nothing identifying.
    final generated =
        'omni${DateTime.now().microsecondsSinceEpoch}'.padRight(24, '0');
    final id = generated.substring(0, 24);
    await _storage.write(key: _deviceIdKey, value: id);
    return id;
  }
}
