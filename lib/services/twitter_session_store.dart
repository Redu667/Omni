import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Cookies from a signed-in x.com session.
///
/// `auth_token` is the session itself; `ct0` doubles as X's CSRF token and
/// must be echoed in the `x-csrf-token` header or requests are rejected.
class TwitterSession {
  const TwitterSession({
    required this.authToken,
    required this.csrfToken,
    this.screenName,
  });

  final String authToken;
  final String csrfToken;

  /// Handle of whoever signed in, shown so it's obvious which account is
  /// in use. Not required for requests.
  final String? screenName;

  String get cookieHeader => 'auth_token=$authToken; ct0=$csrfToken';

  Map<String, dynamic> toJson() => {
        'authToken': authToken,
        'csrfToken': csrfToken,
        'screenName': screenName,
      };

  factory TwitterSession.fromJson(Map<String, dynamic> json) => TwitterSession(
        authToken: json['authToken'] as String,
        csrfToken: json['csrfToken'] as String,
        screenName: json['screenName'] as String?,
      );
}

class TwitterSessionStore {
  TwitterSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _key = 'omni_twitter_session_v1';
  final FlutterSecureStorage _storage;

  Future<TwitterSession?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return TwitterSession.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> save(TwitterSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  Future<void> clear() => _storage.delete(key: _key);
}
