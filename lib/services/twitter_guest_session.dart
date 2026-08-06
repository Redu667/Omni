import 'dart:convert';

import 'package:http/http.dart' as http;

import 'twitter_guest_config.dart';

/// Holds an anonymous guest token, the same credential X's own web frontend
/// obtains for logged-out visitors. Tokens are good for a few hours, so one
/// is cached and shared across every Twitter source in a refresh.
class TwitterGuestSession {
  TwitterGuestSession({Duration? lifetime})
      : _lifetime = lifetime ?? const Duration(hours: 2);

  final Duration _lifetime;
  String? _token;
  DateTime? _obtainedAt;

  String? get cachedToken => _token;

  bool get _isFresh =>
      _token != null &&
      _obtainedAt != null &&
      DateTime.now().difference(_obtainedAt!) < _lifetime;

  /// Returns a usable guest token, activating a new one when needed.
  /// Pass [forceRefresh] after X rejects the current token.
  Future<String> token(
    http.Client client,
    TwitterGuestConfig config, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _isFresh) return _token!;

    final res = await client.post(
      Uri.https('api.twitter.com', '/1.1/guest/activate.json'),
      headers: {'Authorization': 'Bearer ${config.bearerToken}'},
    );
    if (res.statusCode != 200) {
      throw TwitterGuestException(
        'Could not start an anonymous session with X (HTTP ${res.statusCode}). '
        'The bearer token may be out of date — update it in Settings → Twitter (X) access.',
      );
    }

    final token =
        (jsonDecode(res.body) as Map<String, dynamic>)['guest_token'] as String?;
    if (token == null || token.isEmpty) {
      throw TwitterGuestException('X returned no guest token.');
    }

    _token = token;
    _obtainedAt = DateTime.now();
    return token;
  }

  void invalidate() {
    _token = null;
    _obtainedAt = null;
  }
}

class TwitterGuestException implements Exception {
  TwitterGuestException(this.message);
  final String message;

  @override
  String toString() => message;
}
