import 'dart:convert';

import 'package:http/http.dart' as http;

/// Keeps Bluesky access tokens alive between refreshes.
///
/// Without this, every refresh signs in again with the app password. That's
/// slow, needlessly hard on their servers, and the kind of thing that gets a
/// client rate limited — `createSession` is one of the endpoints Bluesky
/// throttles hardest.
///
/// Access tokens last about two hours; the refresh token lasts far longer
/// and can mint a new one without the password.
class BlueskySessions {
  BlueskySessions({this.host = 'bsky.social'});

  final String host;
  final _byIdentifier = <String, _Session>{};

  /// Access tokens are good for roughly two hours. Renewing early costs one
  /// cheap request and avoids a mid-refresh expiry.
  static const _reuseFor = Duration(minutes: 90);

  /// Returns a usable access token, signing in only when it has to.
  Future<String> accessToken(
    http.Client client,
    String identifier,
    String appPassword, {
    bool forceRefresh = false,
  }) async {
    final existing = _byIdentifier[identifier];
    if (!forceRefresh && existing != null && existing.isFresh) {
      return existing.access;
    }

    final refreshToken = existing?.refresh;
    if (refreshToken != null) {
      final renewed = await _refresh(client, refreshToken);
      if (renewed != null) {
        _byIdentifier[identifier] = renewed;
        return renewed.access;
      }
      // The refresh token expired or was revoked; fall through and sign in.
    }

    final created = await _create(client, identifier, appPassword);
    _byIdentifier[identifier] = created;
    return created.access;
  }

  /// Drops the cached token for [identifier] so the next call signs in
  /// again — for when Bluesky rejects a token we thought was good.
  void invalidate(String identifier) => _byIdentifier.remove(identifier);

  Future<_Session> _create(
      http.Client client, String identifier, String appPassword) async {
    final res = await client.post(
      Uri.https(host, '/xrpc/com.atproto.server.createSession'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'identifier': identifier, 'password': appPassword}),
    );
    if (res.statusCode != 200) {
      throw BlueskyAuthException(res.statusCode);
    }
    final session = _Session.from(jsonDecode(res.body) as Map<String, dynamic>);
    if (session == null) throw BlueskyAuthException(res.statusCode);
    return session;
  }

  /// Returns null when the refresh token is no longer usable, which is a
  /// normal end of life rather than an error worth surfacing.
  Future<_Session?> _refresh(http.Client client, String refreshJwt) async {
    try {
      final res = await client.post(
        Uri.https(host, '/xrpc/com.atproto.server.refreshSession'),
        headers: {'Authorization': 'Bearer $refreshJwt'},
      );
      if (res.statusCode != 200) return null;
      return _Session.from(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

class BlueskyAuthException implements Exception {
  BlueskyAuthException(this.statusCode);
  final int statusCode;

  @override
  String toString() => 'sign-in failed (HTTP $statusCode)';
}

class _Session {
  _Session({
    required this.access,
    required this.issuedAt,
    this.refresh,
  });

  static _Session? from(Map<String, dynamic> body) {
    final access = body['accessJwt'] as String?;
    if (access == null) return null;
    return _Session(
      access: access,
      // Bluesky always sends one, but an access token without it is still
      // usable — it just can't be renewed without the password.
      refresh: body['refreshJwt'] as String?,
      issuedAt: DateTime.now(),
    );
  }

  final String access;
  final String? refresh;
  final DateTime issuedAt;

  bool get isFresh =>
      DateTime.now().difference(issuedAt) < BlueskySessions._reuseFor;
}
