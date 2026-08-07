import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/twitter_session_store.dart';

/// Signs in to x.com in a real browser view and keeps the resulting session
/// cookies.
///
/// The login itself happens on X's own pages — Omni never sees the password,
/// only the cookies the site sets afterwards. `auth_token` is HttpOnly, so it
/// has to come from the platform cookie store rather than from JavaScript.
class TwitterLoginScreen extends StatefulWidget {
  const TwitterLoginScreen({super.key});

  @override
  State<TwitterLoginScreen> createState() => _TwitterLoginScreenState();
}

class _TwitterLoginScreenState extends State<TwitterLoginScreen> {
  final _cookieManager = CookieManager.instance();
  bool _capturing = false;

  Future<void> _tryCapture(Uri? url) async {
    if (_capturing || !mounted) return;

    for (final host in const ['https://x.com', 'https://twitter.com']) {
      final cookies = await _cookieManager.getCookies(url: WebUri(host));
      String? valueOf(String name) {
        for (final c in cookies) {
          if (c.name == name && '${c.value}'.isNotEmpty) return '${c.value}';
        }
        return null;
      }

      final authToken = valueOf('auth_token');
      final csrf = valueOf('ct0');
      if (authToken == null || csrf == null) continue;

      _capturing = true;
      final session = TwitterSession(
        authToken: authToken,
        csrfToken: csrf,
        screenName: valueOf('twid')
            ?.replaceAll(RegExp(r'^u%3D|^u='), '')
            .replaceAll('"', ''),
      );
      if (mounted) Navigator.of(context).pop(session);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in to X'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(38),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Omni never sees your password — only the session cookie X sets '
              'once you are signed in.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        ),
      ),
      body: InAppWebView(
        initialUrlRequest:
            URLRequest(url: WebUri('https://x.com/i/flow/login')),
        initialSettings: InAppWebViewSettings(
          userAgent:
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/124.0.0.0 Mobile Safari/537.36',
          javaScriptEnabled: true,
          thirdPartyCookiesEnabled: true,
        ),
        onLoadStop: (_, url) => _tryCapture(url),
        onUpdateVisitedHistory: (_, url, _) => _tryCapture(url),
      ),
    );
  }
}
