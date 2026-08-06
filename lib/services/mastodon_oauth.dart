import 'dart:convert';

import 'package:http/http.dart' as http;

/// In-app OAuth sign-in for Mastodon instances.
///
/// Flow: register Omni as an app on the instance, send the user to the
/// instance's authorize page in the browser, catch the `dev.omni://` redirect
/// via deep link, then exchange the code for an access token.
class MastodonOAuth {
  MastodonOAuth(this.httpClient);

  final http.Client httpClient;

  static const redirectUri = 'dev.omni://oauth-callback';
  static const scopes = 'read';

  static String normalizeInstance(String input) => input
      .trim()
      .replaceAll(RegExp(r'^https?://'), '')
      .replaceAll(RegExp(r'/.*$'), '')
      .replaceAll('@', '');

  /// Registers Omni on the instance; returns client credentials.
  Future<({String clientId, String clientSecret})> registerApp(
      String instance) async {
    final res = await httpClient.post(
      Uri.https(instance, '/api/v1/apps'),
      body: {
        'client_name': 'Omni',
        'redirect_uris': redirectUri,
        'scopes': scopes,
        'website': 'https://github.com/Redu667/Omni',
      },
    );
    if (res.statusCode != 200) {
      throw MastodonOAuthException(
          'Could not register with $instance (HTTP ${res.statusCode}). '
          'Is that a Mastodon instance?');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      clientId: json['client_id'] as String,
      clientSecret: json['client_secret'] as String,
    );
  }

  Uri authorizationUrl(String instance, String clientId) =>
      Uri.https(instance, '/oauth/authorize', {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': scopes,
      });

  /// Exchanges the authorization code from the redirect for an access token.
  Future<String> exchangeCode({
    required String instance,
    required String clientId,
    required String clientSecret,
    required String code,
  }) async {
    final res = await httpClient.post(
      Uri.https(instance, '/oauth/token'),
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'client_id': clientId,
        'client_secret': clientSecret,
        'redirect_uri': redirectUri,
        'scope': scopes,
      },
    );
    if (res.statusCode != 200) {
      throw MastodonOAuthException(
          'Sign-in failed (HTTP ${res.statusCode} exchanging the code).');
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['access_token']
        as String;
  }

  /// The signed-in account's handle, e.g. "user@instance" — used to label
  /// the source. Returns null if the lookup fails; the source still works.
  Future<String?> verifyCredentials(String instance, String token) async {
    final res = await httpClient.get(
      Uri.https(instance, '/api/v1/accounts/verify_credentials'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) return null;
    final acct =
        (jsonDecode(res.body) as Map<String, dynamic>)['acct'] as String?;
    if (acct == null) return null;
    return acct.contains('@') ? acct : '$acct@$instance';
  }
}

class MastodonOAuthException implements Exception {
  MastodonOAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
