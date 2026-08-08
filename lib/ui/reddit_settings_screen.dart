import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';

/// Lets the user supply a Reddit app ID, which is the difference between
/// being blocked as an anonymous caller and not.
class RedditSettingsScreen extends StatefulWidget {
  const RedditSettingsScreen({super.key});

  @override
  State<RedditSettingsScreen> createState() => _RedditSettingsScreenState();
}

class _RedditSettingsScreenState extends State<RedditSettingsScreen> {
  late final TextEditingController _clientId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _clientId = TextEditingController(text: context.read<AppState>().redditClientId ?? '');
  }

  @override
  void dispose() {
    _clientId.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    await context.read<AppState>().setRedditClientId(_clientId.text);
    if (mounted) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
        content: Text(_clientId.text.trim().isEmpty
            ? 'Cleared — Reddit will be read anonymously again.'
            : 'Saved. Reddit sources will use it on the next refresh.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Reddit access')),
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
                  Text('Why this helps', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    'Reddit refuses anonymous requests for its JSON listings '
                    'more and more often, including on plainly public '
                    'subreddits — that is the 403 you have been seeing. Omni '
                    'falls back to Reddit\'s Atom feeds, which work but carry '
                    'no scores, comment counts or post text.\n\n'
                    'An app ID makes requests authenticated, which Reddit '
                    'does not block, and restores the full listing. It needs '
                    'no Reddit account, password or permissions.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('How to get one', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            '1. Open reddit.com/prefs/apps\n'
            '2. Choose "create another app"\n'
            '3. Pick the "installed app" type\n'
            '4. Put anything in the redirect URI — http://localhost is fine\n'
            '5. Copy the ID shown under the app name, not the secret',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open Reddit app settings'),
            onPressed: () => launchUrl(
              Uri.parse('https://www.reddit.com/prefs/apps'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _clientId,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'App ID',
              helperText: 'Leave empty to go back to anonymous requests',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
