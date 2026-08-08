import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/feed_item.dart';
import 'video_player_screen.dart';

/// Full-screen images: pinch to zoom, drag to pan, swipe between them.
///
/// Alt text sits under the image rather than being hidden in a menu — it's
/// the author describing their own picture, which is often the most
/// informative thing on screen.
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.media,
    this.initialIndex = 0,
  });

  final List<MediaItem> media;
  final int initialIndex;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  /// Zooming has to disable paging, or a pan gesture turns into a swipe.
  final _zoom = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(() {
      final scale = _zoom.value.getMaxScaleOnAxis();
      final zoomed = scale > 1.01;
      if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.media[_index];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.media.length > 1
              ? '${_index + 1} of ${widget.media.length}'
              : '',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Open in browser',
            onPressed: () => launchUrl(Uri.parse(current.url),
                mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            physics: _zoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            onPageChanged: (i) {
              // Reset zoom when moving to another image.
              _zoom.value = Matrix4.identity();
              setState(() => _index = i);
            },
            itemCount: widget.media.length,
            itemBuilder: (_, i) => InteractiveViewer(
              // Zooming a video's poster frame would be a lie about what's
              // on screen, so only images pan and scale.
              transformationController:
                  i == _index && !widget.media[i].kind.isVideo ? _zoom : null,
              minScale: 1,
              maxScale: widget.media[i].kind.isVideo ? 1 : 5,
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CachedNetworkImage(
                      imageUrl: widget.media[i].previewUrl,
                      fit: BoxFit.contain,
                      placeholder: (_, _) => const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                      errorWidget: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: Colors.white54, size: 48),
                      ),
                    ),
                    if (widget.media[i].kind.isVideo)
                      _PlayButton(media: widget.media[i]),
                  ],
                ),
              ),
            ),
          ),
          if (current.hasAlt && !_zoomed)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black.withValues(alpha: 0.65),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: SafeArea(
                  top: false,
                  child: Text(
                    current.alt!,
                    style: const TextStyle(color: Colors.white70, height: 1.35),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Sits over a video's poster frame in the gallery.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.media});

  final MediaItem media;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => VideoPlayerScreen(media: media)),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Icon(Icons.play_arrow, size: 44, color: Colors.white),
        ),
      ),
    );
  }
}
