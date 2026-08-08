import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/feed_item.dart';
import '../state/app_state.dart';
import 'profile_screen.dart';

/// The actions available on a post, shared by the timeline and the detail
/// view so long-pressing anywhere offers the same things.
Future<void> showPostActions(BuildContext context, FeedItem item) async {
  final state = context.read<AppState>();
  final saved = state.isSaved(item);
  final canOpenProfile = state.supportsAuthorFeed(item);
  final author = item.handle ?? item.author;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
            title: Text(saved ? 'Remove from saved' : 'Save post'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(sheetContext).pop();
              final nowSaved = await state.toggleSaved(item);
              messenger.showSnackBar(SnackBar(
                content: Text(nowSaved ? 'Saved' : 'Removed from saved'),
              ));
            },
          ),
          if (canOpenProfile)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text('Posts by $author'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ProfileScreen(item: item)));
              },
            ),
          ListTile(
            leading: const Icon(Icons.person_off_outlined),
            title: Text('Mute $author'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(sheetContext).pop();
              await state.muteAccount(author);
              messenger
                  .showSnackBar(SnackBar(content: Text('Muted $author')));
            },
          ),
          if (item.url != null) ...[
            ListTile(
              leading: const Icon(Icons.open_in_browser),
              title: const Text('Open in browser'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                launchUrl(Uri.parse(item.url!),
                    mode: LaunchMode.externalApplication);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copy link'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.of(sheetContext).pop();
                await Clipboard.setData(ClipboardData(text: item.url!));
                messenger.showSnackBar(
                    const SnackBar(content: Text('Link copied')));
              },
            ),
          ],
        ],
      ),
    ),
  );
}
