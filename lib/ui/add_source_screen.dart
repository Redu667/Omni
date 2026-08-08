import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/feed_source.dart';
import '../models/network.dart';
import '../services/mastodon_oauth.dart';
import '../services/source_client.dart';
import '../state/app_state.dart';
import 'twitter_settings_screen.dart';

class AddSourceScreen extends StatefulWidget {
  const AddSourceScreen({super.key, this.initialNetwork});

  final Network? initialNetwork;

  @override
  State<AddSourceScreen> createState() => _AddSourceScreenState();
}

class _AddSourceScreenState extends State<AddSourceScreen> {
  Network? _network;

  @override
  void initState() {
    super.initState();
    _network = widget.initialNetwork;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_network == null
            ? 'Add source'
            : 'Add ${_network!.label} source'),
      ),
      body: _network == null
          ? _NetworkPicker(onPicked: (n) => setState(() => _network = n))
          : _SourceForm(network: _network!),
    );
  }
}

class _NetworkPicker extends StatelessWidget {
  const _NetworkPicker({required this.onPicked});

  final ValueChanged<Network> onPicked;

  static const _subtitles = {
    Network.mastodon: 'Sign in for your home timeline, or follow an instance',
    Network.bluesky: 'Home timeline (app password) or a public author feed',
    Network.reddit: 'Any subreddit — no account needed',
    Network.twitter: 'Public tweets without an account, or the official API',
    Network.rss: 'A feed URL, or any website — Omni finds the feed',
  };

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        for (final network in Network.values)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: network.color.withValues(alpha: 0.15),
              child: Icon(network.icon, color: network.color),
            ),
            title: Text(network.label),
            subtitle: Text(_subtitles[network]!),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onPicked(network),
          ),
      ],
    );
  }
}

class _SourceForm extends StatefulWidget {
  const _SourceForm({required this.network});

  final Network network;

  @override
  State<_SourceForm> createState() => _SourceFormState();
}

class _FieldSpec {
  const _FieldSpec(this.key, this.label,
      {this.hint, this.required = false, this.obscure = false});

  final String key;
  final String label;
  final String? hint;
  final bool required;
  final bool obscure;
}

class _SourceFormState extends State<_SourceForm> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  bool _saving = false;
  String? _error;

  /// Twitter defaults to anonymous guest access; the official API is opt-in
  /// because it needs a paid plan.
  bool _twitterOfficial = false;

  /// Which Reddit listing to pull. Matches Reddit's own default.
  String _redditSort = 'hot';

  // Mastodon OAuth state, alive while the browser round-trip is in flight.
  final _oauth = MastodonOAuth(http.Client());
  StreamSubscription<Uri>? _linkSub;
  ({String instance, String clientId, String clientSecret})? _pendingOauth;
  String? _oauthAccount;

  List<_FieldSpec> get _fields => switch (widget.network) {
        Network.mastodon => const [
            _FieldSpec('instance', 'Instance',
                hint: 'mastodon.social', required: true),
            _FieldSpec('accessToken', 'Access token (optional)',
                hint: 'Filled automatically when you sign in below',
                obscure: true),
          ],
        Network.bluesky => const [
            _FieldSpec('handle', 'Handle (public feed)',
                hint: 'someone.bsky.social'),
            _FieldSpec('identifier', 'Your handle or email (home timeline)',
                hint: 'you.bsky.social'),
            _FieldSpec('appPassword', 'App password',
                hint: 'From Settings → App Passwords', obscure: true),
          ],
        Network.reddit => const [
            _FieldSpec('subreddit', 'Subreddit(s)',
                hint: 'flutter or flutter+androiddev', required: true),
          ],
        Network.twitter => [
            const _FieldSpec('usernames', 'Usernames',
                hint: 'nasa, flutterdev', required: true),
            if (_twitterOfficial)
              const _FieldSpec('bearerToken', 'API bearer token',
                  hint: 'From developer.x.com (paid read access)',
                  required: true,
                  obscure: true),
          ],
        Network.rss => const [
            _FieldSpec('url', 'Feed or website URL',
                hint: 'example.com — Omni finds the feed', required: true),
          ],
      };

  TextEditingController _controller(String key) =>
      _controllers.putIfAbsent(key, TextEditingController.new);

  @override
  void initState() {
    super.initState();
    if (widget.network == Network.mastodon) {
      _linkSub = AppLinks().uriLinkStream.listen(_onDeepLink);
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _oauth.httpClient.close();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _startOauth() async {
    final instance =
        MastodonOAuth.normalizeInstance(_controller('instance').text);
    if (instance.isEmpty) {
      setState(() => _error = 'Enter your instance first (e.g. mastodon.social).');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final app = await _oauth.registerApp(instance);
      _pendingOauth = (
        instance: instance,
        clientId: app.clientId,
        clientSecret: app.clientSecret,
      );
      await launchUrl(
        _oauth.authorizationUrl(instance, app.clientId),
        mode: LaunchMode.externalApplication,
      );
    } on MastodonOAuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not reach $instance: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onDeepLink(Uri uri) async {
    final pending = _pendingOauth;
    final code = uri.queryParameters['code'];
    if (pending == null || uri.host != 'oauth-callback' || code == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      final token = await _oauth.exchangeCode(
        instance: pending.instance,
        clientId: pending.clientId,
        clientSecret: pending.clientSecret,
        code: code,
      );
      _controller('accessToken').text = token;
      _controller('instance').text = pending.instance;
      _oauthAccount =
          await _oauth.verifyCredentials(pending.instance, token);
      _pendingOauth = null;
      if (mounted) setState(() => _error = null);
    } on MastodonOAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _defaultName(Map<String, String> params) => switch (widget.network) {
        Network.mastodon => params['accessToken']?.isNotEmpty == true
            ? (_oauthAccount != null
                ? '@$_oauthAccount'
                : 'Home · ${params['instance']}')
            : 'Public · ${params['instance']}',
        Network.bluesky => params['identifier']?.isNotEmpty == true
            ? 'Bluesky home'
            : '@${params['handle']}',
        Network.reddit => params['sort'] == null || params['sort'] == 'hot'
            ? 'r/${params['subreddit']}'
            : 'r/${params['subreddit']} · ${params['sort']}',
        Network.twitter => 'X · ${params['usernames']}',
        Network.rss => Uri.tryParse(params['url'] ?? '')?.host ?? 'RSS feed',
      };

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final params = {
      for (final f in _fields)
        if (_controller(f.key).text.trim().isNotEmpty)
          f.key: _controller(f.key).text.trim(),
    };
    if (widget.network == Network.mastodon) {
      params['instance'] = MastodonOAuth.normalizeInstance(params['instance']!);
    }
    if (widget.network == Network.twitter) {
      params['mode'] = _twitterOfficial ? 'official' : 'guest';
    }
    if (widget.network == Network.reddit) {
      params['sort'] = _redditSort;
    }

    if (widget.network == Network.bluesky &&
        params['handle'] == null &&
        (params['identifier'] == null || params['appPassword'] == null)) {
      setState(() => _error =
          'Enter a handle for a public feed, or both sign-in fields for your home timeline.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final source = FeedSource(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      network: widget.network,
      displayName: _defaultName(params),
      params: params,
    );

    final state = context.read<AppState>();
    final navigator = Navigator.of(context);
    try {
      await state.validateAndAddSource(source);
      if (mounted) navigator.pop();
    } on SourceFetchException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not load this source: ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not load this source: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final field in _fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextFormField(
                controller: _controller(field.key),
                obscureText: field.obscure,
                autocorrect: !field.obscure,
                decoration: InputDecoration(
                  labelText: field.label,
                  hintText: field.hint,
                  border: const OutlineInputBorder(),
                ),
                validator: field.required
                    ? (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null
                    : null,
              ),
            ),
          if (widget.network == Network.mastodon) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.login),
              label: Text(_oauthAccount != null
                  ? 'Signed in as @$_oauthAccount'
                  : 'Sign in with your instance'),
              onPressed: _saving || _oauthAccount != null ? null : _startOauth,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              child: Text(
                'Sign in for your personal home timeline, or leave the token '
                'empty to follow the instance\'s public timeline.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ],
          if (widget.network == Network.reddit)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: DropdownButtonFormField<String>(
                value: _redditSort,
                decoration: const InputDecoration(
                  labelText: 'Sort',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'hot', child: Text('Hot')),
                  DropdownMenuItem(value: 'new', child: Text('New')),
                  DropdownMenuItem(value: 'top', child: Text('Top')),
                  DropdownMenuItem(value: 'rising', child: Text('Rising')),
                ],
                onChanged: (v) =>
                    setState(() => _redditSort = v ?? 'hot'),
              ),
            ),
          if (widget.network == Network.twitter) ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.public, size: 18),
                  label: Text('Anonymous'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.vpn_key, size: 18),
                  label: Text('Official API'),
                ),
              ],
              selected: {_twitterOfficial},
              onSelectionChanged: (s) =>
                  setState(() => _twitterOfficial = s.first),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(
                _twitterOfficial
                    ? 'Uses X\'s official API v2. Reliable, but read access '
                        'requires a paid API plan.'
                    : 'Reads public tweets the way a logged-out browser does — '
                        'no account or API plan. X changes its internals '
                        'periodically, so this breaks from time to time; when '
                        'it does, refresh the values in settings below.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
            if (!_twitterOfficial)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Anonymous access settings'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const TwitterSettingsScreen()),
                  ),
                ),
              ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Check & add source'),
          ),
        ],
      ),
    );
  }
}
