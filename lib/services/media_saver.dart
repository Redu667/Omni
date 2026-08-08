import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/feed_item.dart';

/// Puts a post's picture or video in the device gallery.
///
/// Downloads it here rather than handing the URL to the system downloader,
/// because several of these networks only serve media to a request that
/// looks like a reader rather than a download manager.
class MediaSaver {
  MediaSaver({
    http.Client? httpClient,
    this.maxBytes = 200 * 1024 * 1024,
    Future<Directory> Function()? tempDirectory,
    Future<void> Function(List<int> bytes, String name)? saveImage,
    Future<void> Function(String path)? saveVideo,
    Future<bool> Function()? hasAccess,
    Future<bool> Function()? requestAccess,
  })  : _http = httpClient ?? http.Client(),
        _tempDirectory = tempDirectory ?? getTemporaryDirectory,
        _saveImage = saveImage ??
            ((bytes, name) =>
                Gal.putImageBytes(Uint8List.fromList(bytes), name: name)),
        _saveVideo = saveVideo ?? Gal.putVideo,
        _hasAccess = hasAccess ?? Gal.hasAccess,
        _requestAccess = requestAccess ?? Gal.requestAccess;

  final http.Client _http;
  final int maxBytes;
  final Future<Directory> Function() _tempDirectory;
  final Future<void> Function(List<int> bytes, String name) _saveImage;
  final Future<void> Function(String path) _saveVideo;
  final Future<bool> Function() _hasAccess;
  final Future<bool> Function() _requestAccess;

  /// Saves [media], returning the message to show. Throws [SaveException]
  /// with something the reader can act on.
  Future<String> save(MediaItem media) async {
    // A streaming playlist isn't a file — Bluesky video and Reddit's HLS
    // are manifests pointing at hundreds of segments, and "saving" one
    // would produce a few kilobytes of text that plays nowhere.
    if (_isPlaylist(media.url)) {
      throw SaveException(
          'This video is streamed rather than served as a file, so it '
          "can't be saved. Opening it in your browser will let you keep it "
          'if the site allows.');
    }

    if (!await _hasAccess() && !await _requestAccess()) {
      throw SaveException('Omni needs permission to add to your gallery.');
    }

    final uri = Uri.tryParse(media.url);
    if (uri == null) throw SaveException("That link doesn't point anywhere.");

    final http.Response res;
    try {
      res = await _http.get(uri, headers: {
        'User-Agent': 'Omni/1.0 (+feed reader)',
      });
    } catch (_) {
      throw SaveException("Couldn't download it — check your connection.");
    }
    if (res.statusCode != 200) {
      throw SaveException('The server answered HTTP ${res.statusCode}.');
    }
    if (res.bodyBytes.length > maxBytes) {
      throw SaveException('That file is too large to save.');
    }

    final name = _nameFor(uri);
    try {
      if (media.kind == MediaKind.image) {
        await _saveImage(res.bodyBytes, name);
        return 'Saved to your gallery';
      }

      // Video goes through a file: the gallery wants a path, not bytes.
      final dir = await _tempDirectory();
      final file = File('${dir.path}/$name${_extensionOf(uri) ?? '.mp4'}');
      await file.writeAsBytes(res.bodyBytes);
      try {
        await _saveVideo(file.path);
      } finally {
        // Leaving a copy in the cache would double what this costs on disk.
        if (await file.exists()) await file.delete();
      }
      return 'Saved to your gallery';
    } on GalException catch (e) {
      throw SaveException(switch (e.type) {
        GalExceptionType.accessDenied =>
          'Omni needs permission to add to your gallery.',
        GalExceptionType.notEnoughSpace => 'There is no room left on the device.',
        GalExceptionType.notSupportedFormat =>
          "Your gallery doesn't accept this kind of file.",
        _ => "Couldn't save it to the gallery.",
      });
    }
  }

  static bool _isPlaylist(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return path.endsWith('.m3u8') || path.endsWith('.mpd');
  }

  static String? _extensionOf(Uri uri) {
    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final dot = last.lastIndexOf('.');
    return dot <= 0 ? null : last.substring(dot);
  }

  /// A stable, filesystem-safe name. The gallery shows it, so it should say
  /// where the file came from rather than being a hash.
  static String _nameFor(Uri uri) {
    final last = uri.pathSegments.isEmpty ? 'omni' : uri.pathSegments.last;
    final dot = last.lastIndexOf('.');
    final stem = dot <= 0 ? last : last.substring(0, dot);
    final safe = stem.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return safe.isEmpty ? 'omni' : 'omni_$safe';
  }

  void dispose() => _http.close();
}

class SaveException implements Exception {
  SaveException(this.message);
  final String message;

  @override
  String toString() => message;
}
