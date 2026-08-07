import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/twitter_guest_config.dart';
import '../services/twitter_session_store.dart';
import '../state/app_state.dart';
import 'twitter_login_screen.dart';

/// Lets the user refresh the values X rotates out from under anonymous
/// clients. Without this screen, every rotation would need an app release.
class TwitterSettingsScreen extends StatefulWidget {
  const TwitterSettingsScreen({super.key});

  @override
  State<TwitterSettingsScreen> createState() => _TwitterSettingsScreenState();
}

class _TwitterSettingsScreenState extends State<TwitterSettingsScreen> {
  late final TextEditingController _bearer;
  late final TextEditingController _userByScreenName;
  late final TextEditingController _userTweets;
  late final TextEditingController _features;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppState>().twitterConfig;
    _bearer = TextEditingController(text: config.bearerToken);
    _userByScreenName =
        TextEditingController(text: config.userByScreenNameQueryId);
    _userTweets = TextEditingController(text: config.userTweetsQueryId);
    _features = TextEditingController(text: config.featuresJson);
  }

  @override
  void dispose() {
    _bearer.dispose();
    _userByScreenName.dispose();
    _userTweets.dispose();
    _features.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final candidate = TwitterGuestConfig(
      bearerToken: _bearer.text.trim(),
      userByScreenNameQueryId: _userByScreenName.text.trim(),
      userTweetsQueryId: _userTweets.text.trim(),
      featuresJson: _features.text.trim(),
    );
    final messenger = ScaffoldMessenger.of(context);
    if (!candidate.featuresJsonIsValid) {
      messenger.showSnackBar(const SnackBar(
          content: Text('The feature flags need to be a valid JSON object.')));
      return;
    }

    setState(() => _saving = true);
    await context.read<AppState>().updateTwitterConfig(candidate);
    if (mounted) {
      setState(() => _saving = false);
      messenger.showSnackBar(const SnackBar(content: Text('Saved.')));
    }
  }

  void _resetToDefaults() {
    setState(() {
      _bearer.text = TwitterGuestConfig.defaultBearerToken;
      _userByScreenName.text =
          TwitterGuestConfig.defaultUserByScreenNameQueryId;
      _userTweets.text = TwitterGuestConfig.defaultUserTweetsQueryId;
      _features.text = TwitterGuestConfig.defaultFeaturesJson;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Twitter (X) access'),
        actions: [
          TextButton(
            onPressed: _resetToDefaults,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Why this screen exists',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    'Omni reads public tweets the same way x.com does for a '
                    'logged-out visitor: it activates an anonymous guest token '
                    'and calls X\'s internal endpoints. Those endpoints are '
                    'identified by query IDs that change whenever X ships a '
                    'new frontend build. When Twitter sources start failing, '
                    'paste current values here — no app update needed.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Squawker'),
                        onPressed: () => launchUrl(
                          Uri.parse('https://github.com/j-fbriere/squawker'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Nitter'),
                        onPressed: () => launchUrl(
                          Uri.parse('https://github.com/zedeus/nitter'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _AccountSection(),
          const SizedBox(height: 20),
          Text('Advanced', style: theme.textTheme.titleSmall),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Text(
              'Only needed if fetches start failing. Signing in above fixes '
              'most problems on its own.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          _Field(
            controller: _userTweets,
            label: 'UserTweets query ID',
            help: 'Fetches an account\'s timeline. Rotates most often.',
          ),
          _Field(
            controller: _userByScreenName,
            label: 'UserByScreenName query ID',
            help: 'Turns a @handle into the numeric ID the timeline call needs.',
          ),
          _Field(
            controller: _bearer,
            label: 'Guest bearer token',
            help: 'The public token x.com ships to logged-out visitors. '
                'Rarely changes.',
            maxLines: 3,
          ),
          _Field(
            controller: _features,
            label: 'Feature flags (JSON)',
            help: 'X rejects requests missing a flag it expects. Extra flags '
                'are harmless, so err on the side of including more.',
            maxLines: 10,
            monospace: true,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save and refresh'),
          ),
          const SizedBox(height: 16),
          Text(
            'Heads up: anonymous access is not a supported X interface and it '
            'breaks periodically by design. It is also rate limited, so a '
            'handful of accounts works far better than dozens.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

/// Sign-in is the headline control here: X serves live timelines to accounts
/// and increasingly stale ones to anonymous callers.
class _AccountSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final account = state.twitterAccount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(account != null ? Icons.check_circle : Icons.person_outline,
                    color: account != null
                        ? Colors.green
                        : theme.colorScheme.outline),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    account != null ? 'Signed in to X' : 'Not signed in',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              account != null
                  ? 'Timelines are fetched as your account, which is what keeps '
                      'them current.'
                  : 'Anonymous access is served a stale timeline by X — often '
                      'posts a year old. Signing in fetches the live one.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (account == null)
              FilledButton.icon(
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Sign in to X'),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final appState = context.read<AppState>();
                  final session = await Navigator.of(context).push<TwitterSession>(
                    MaterialPageRoute(
                        builder: (_) => const TwitterLoginScreen()),
                  );
                  if (session == null) return;
                  await appState.signInToTwitter(session);
                  messenger.showSnackBar(
                      const SnackBar(content: Text('Signed in to X.')));
                },
              )
            else
              OutlinedButton.icon(
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Sign out'),
                onPressed: () => context.read<AppState>().signOutOfTwitter(),
              ),
            const SizedBox(height: 10),
            Text(
              'Using an account this way is against X\'s terms of service, and '
              'accounts have been suspended for it. Consider a secondary '
              'account rather than one you rely on.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.help,
    this.maxLines = 1,
    this.monospace = false,
  });

  final TextEditingController controller;
  final String label;
  final String help;
  final int maxLines;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        autocorrect: false,
        enableSuggestions: false,
        style: monospace ? const TextStyle(fontFamily: 'monospace', fontSize: 12) : null,
        decoration: InputDecoration(
          labelText: label,
          helperText: help,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
