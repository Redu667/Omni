import 'package:flutter/material.dart';

import '../models/feed_item.dart';
import '../services/media_saver.dart';

/// One saver for the app, so a repeated save reuses the connection.
final mediaSaver = MediaSaver();

/// A save button for the image viewer and the video player.
///
/// Both screens are dark overlays over the media, so this styles itself for
/// that rather than taking the app's colours.
class SaveMediaButton extends StatefulWidget {
  const SaveMediaButton({super.key, required this.media});

  final MediaItem media;

  @override
  State<SaveMediaButton> createState() => _SaveMediaButtonState();
}

class _SaveMediaButtonState extends State<SaveMediaButton> {
  bool _saving = false;
  bool _saved = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await mediaSaver.save(widget.media);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
      });
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on SaveException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        // These messages explain a limitation rather than a slip, so they
        // are worth long enough to actually read.
        duration: const Duration(seconds: 6),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't save it.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_saving) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
    }

    return IconButton(
      icon: Icon(_saved ? Icons.download_done : Icons.download),
      tooltip: _saved ? 'Saved' : 'Save to gallery',
      onPressed: _saved ? null : _save,
    );
  }
}
