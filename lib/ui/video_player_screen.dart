import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/feed_item.dart';

/// Plays a video attached to a post.
///
/// Deliberately plain: play/pause, a scrubber, and mute. Omni is a reader,
/// and the alternative to a simple player was no video at all.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.media});

  final MediaItem media;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _controller;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.media.url));
    _start();
  }

  Future<void> _start() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      // A silent looping clip is what a GIF is; anything else plays once
      // with sound, as posted.
      await _controller.setLooping(widget.media.kind == MediaKind.gif);
      if (widget.media.kind == MediaKind.gif) {
        await _controller.setVolume(0);
      }
      await _controller.play();
      setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Open in browser',
            onPressed: () => launchUrl(Uri.parse(widget.media.url),
                mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Center(child: _body()),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined,
                color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            const Text(
              "This video wouldn't play here.",
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => launchUrl(Uri.parse(widget.media.url),
                  mode: LaunchMode.externalApplication),
              child: const Text('Open it in your browser'),
            ),
          ],
        ),
      );
    }

    if (!_ready) {
      // The poster frame while it buffers, so the screen isn't just black.
      return Stack(
        alignment: Alignment.center,
        children: [
          if (widget.media.thumbnailUrl != null)
            CachedNetworkImage(
              imageUrl: widget.media.thumbnailUrl!,
              fit: BoxFit.contain,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          const CircularProgressIndicator(color: Colors.white),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(_controller),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _controller.value.isPlaying
                    ? _controller.pause()
                    : _controller.play()),
                child: ValueListenableBuilder(
                  valueListenable: _controller,
                  builder: (_, value, _) => AnimatedOpacity(
                    opacity: value.isPlaying ? 0 : 1,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(Icons.play_arrow,
                        size: 64, color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ),
        VideoProgressIndicator(
          _controller,
          allowScrubbing: true,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        if (widget.media.kind != MediaKind.gif)
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (_, value, _) => IconButton(
              icon: Icon(
                value.volume == 0 ? Icons.volume_off : Icons.volume_up,
                color: Colors.white,
              ),
              tooltip: value.volume == 0 ? 'Unmute' : 'Mute',
              onPressed: () => _controller.setVolume(value.volume == 0 ? 1 : 0),
            ),
          ),
        if (widget.media.hasAlt)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Text(
              widget.media.alt!,
              style: const TextStyle(color: Colors.white70, height: 1.35),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}
