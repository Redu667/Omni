import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/feed_item.dart';

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
            tooltip: 'Open image in browser',
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
              transformationController: i == _index ? _zoom : null,
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: widget.media[i].url,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (_, _, _) => const Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: Colors.white54, size: 48),
                  ),
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
