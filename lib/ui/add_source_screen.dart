import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/feed_source.dart';
import '../models/network.dart';
import '../state/app_state.dart';

class AddSourceScreen extends StatefulWidget {
  const AddSourceScreen({super.key});

  @override
  State<AddSourceScreen> createState() => _AddSourceScreenState();
}

class _AddSourceScreenState extends State<AddSourceScreen> {
  Network? _network;

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
    Network.mastodon: 'Home timeline (with token) or an instance public feed',
    Network.bluesky: 'Home timeline (app password) or a public author feed',
    Network.reddit: 'Any subreddit — no account needed',
    Network.twitter: 'Via the official API (needs your own bearer token)',
    Network.rss: 'Any RSS or Atom feed URL',
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

  List<_FieldSpec> get _fields => switch (widget.network) {
        Network.mastodon => const [
            _FieldSpec('instance', 'Instance',
                hint: 'mastodon.social', required: true),
            _FieldSpec('accessToken', 'Access token (optional)',
                hint: 'For your home timeline — from Settings → Development',
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
        Network.twitter => const [
            _FieldSpec('bearerToken', 'API bearer token',
                hint: 'From developer.x.com (paid read access)',
                required: true,
                obscure: true),
            _FieldSpec('usernames', 'Usernames',
                hint: 'user1, user2', required: true),
          ],
        Network.rss => const [
            _FieldSpec('url', 'Feed URL',
                hint: 'https://example.com/feed.xml', required: true),
          ],
      };

  TextEditingController _controller(String key) =>
      _controllers.putIfAbsent(key, TextEditingController.new);

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _defaultName(Map<String, String> params) => switch (widget.network) {
        Network.mastodon => params['accessToken']?.isNotEmpty == true
            ? 'Home · ${params['instance']}'
            : 'Public · ${params['instance']}',
        Network.bluesky => params['identifier']?.isNotEmpty == true
            ? 'Bluesky home'
            : '@${params['handle']}',
        Network.reddit => 'r/${params['subreddit']}',
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

    if (widget.network == Network.bluesky &&
        params['handle'] == null &&
        (params['identifier'] == null || params['appPassword'] == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Enter a handle for a public feed, or both sign-in fields for your home timeline.')));
      return;
    }

    setState(() => _saving = true);
    final source = FeedSource(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      network: widget.network,
      displayName: _defaultName(params),
      params: params,
    );

    final state = context.read<AppState>();
    final navigator = Navigator.of(context);
    await state.addSource(source);
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
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
          if (widget.network == Network.twitter)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Note: X removed free API read access. This source only works '
                'with a bearer token from a paid API plan.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Add source'),
          ),
        ],
      ),
    );
  }
}
