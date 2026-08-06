import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/services/mastodon_oauth.dart';

void main() {
  test('normalizeInstance strips scheme, path and @', () {
    expect(MastodonOAuth.normalizeInstance('https://mastodon.social/'),
        'mastodon.social');
    expect(MastodonOAuth.normalizeInstance('mastodon.social/@user'),
        'mastodon.social');
    expect(MastodonOAuth.normalizeInstance(' Fosstodon.org '), 'Fosstodon.org');
  });

  test('registerApp posts client info and returns credentials', () async {
    late http.Request captured;
    final oauth = MastodonOAuth(MockClient((req) async {
      captured = req;
      return http.Response(
          jsonEncode({'client_id': 'cid', 'client_secret': 'sec'}), 200);
    }));

    final app = await oauth.registerApp('mastodon.social');
    expect(captured.url.toString(), 'https://mastodon.social/api/v1/apps');
    expect(captured.bodyFields['redirect_uris'], MastodonOAuth.redirectUri);
    expect(app.clientId, 'cid');
    expect(app.clientSecret, 'sec');
  });

  test('authorizationUrl carries the right query params', () {
    final oauth = MastodonOAuth(MockClient((_) async => http.Response('', 200)));
    final url = oauth.authorizationUrl('mastodon.social', 'cid');
    expect(url.host, 'mastodon.social');
    expect(url.path, '/oauth/authorize');
    expect(url.queryParameters['client_id'], 'cid');
    expect(url.queryParameters['response_type'], 'code');
    expect(url.queryParameters['redirect_uri'], MastodonOAuth.redirectUri);
  });

  test('exchangeCode returns the access token', () async {
    final oauth = MastodonOAuth(MockClient((req) async {
      expect(req.bodyFields['grant_type'], 'authorization_code');
      expect(req.bodyFields['code'], 'the-code');
      return http.Response(jsonEncode({'access_token': 'tok'}), 200);
    }));

    final token = await oauth.exchangeCode(
      instance: 'mastodon.social',
      clientId: 'cid',
      clientSecret: 'sec',
      code: 'the-code',
    );
    expect(token, 'tok');
  });

  test('registerApp throws a readable error on failure', () async {
    final oauth =
        MastodonOAuth(MockClient((_) async => http.Response('nope', 404)));
    expect(
      oauth.registerApp('not-mastodon.example.com'),
      throwsA(isA<MastodonOAuthException>()),
    );
  });

  test('verifyCredentials builds a full handle', () async {
    final oauth = MastodonOAuth(
        MockClient((_) async => http.Response(jsonEncode({'acct': 'me'}), 200)));
    expect(await oauth.verifyCredentials('mastodon.social', 'tok'),
        'me@mastodon.social');
  });
}
