import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/feed_item.dart';
import 'media_remuxer.dart';
import 'reddit_dash.dart';

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
    MediaRemuxer? remuxer,
  })  : _http = httpClient ?? http.Client(),
        _remuxer = remuxer ?? const MediaRemuxer(),
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
  final MediaRemuxer _remuxer;

  /// Saves [media], returning the message to show. Throws [SaveException]
  /// with something the reader can act on.
  Future<String> save(MediaItem media) async {
    // Reddit splits video and audio into separate files, so its "playlist"
    // URLs do lead to something savable — see [_saveRedditVideo].
    final manifestUrl = dashManifestUrlFor(media.url);

    // Anything else streamed is genuinely not a file. Bluesky's HLS is
    // segments with no whole-file equivalent, and "saving" the manifest
    // would produce a few kilobytes of text that plays nowhere.
    if (manifestUrl == null && _isPlaylist(media.url)) {
      throw SaveException(
          'This video is streamed rather than served as a file, so it '
          "can't be saved. Opening it in your browser will let you keep it "
          'if the site allows.');
    }

    if (!await _hasAccess() && !await _requestAccess()) {
      throw SaveException('Omni needs permission to add to your gallery.');
    }

    if (manifestUrl != null && media.kind.isPlayable) {
      return _saveRedditVideo(manifestUrl);
    }

    final uri = Uri.tryParse(media.url);
    if (uri == null) throw SaveException("That link doesn't point anywhere.");

    final http.Response res;
    try {
      res = await _http.get(uri, headers: _headers);
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

  /// Downloads a `v.redd.it` video and its audio, and joins them.
  ///
  /// Reddit serves adaptive streams, so the picture and the sound are
  /// different files. Saving only the video is what makes a saved Reddit
  /// clip silent; this is the whole reason the manifest is consulted rather
  /// than the URL saved directly.
  Future<String> _saveRedditVideo(String manifestUrl) async {
    final manifestUri = Uri.parse(manifestUrl);

    final http.Response manifest;
    try {
      manifest = await _http.get(manifestUri, headers: _headers);
    } catch (_) {
      throw SaveException("Couldn't download it — check your connection.");
    }
    if (manifest.statusCode != 200) {
      throw SaveException(
          'Reddit answered HTTP ${manifest.statusCode} for that video.');
    }

    final tracks = parseDashManifest(manifest.body, manifestUri);
    if (tracks == null) {
      throw SaveException("Couldn't work out where that video is stored.");
    }

    final dir = await _tempDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final videoFile = File('${dir.path}/omni_$stamp.video.mp4');
    final audioFile = File('${dir.path}/omni_$stamp.audio.mp4');
    final outputFile = File('${dir.path}/omni_reddit_$stamp.mp4');

    try {
      await _download(tracks.videoUrl, videoFile);

      var saved = videoFile;
      if (tracks.hasAudio) {
        await _download(tracks.audioUrl!, audioFile);
        final joined = await _remuxer.remux(
          videoPath: videoFile.path,
          audioPath: audioFile.path,
          outputPath: outputFile.path,
        );
        // A failed join still leaves a watchable clip, which beats
        // refusing to save anything.
        if (joined) saved = outputFile;
      }

      await _saveVideo(saved.path);
      return tracks.hasAudio && saved == outputFile
          ? 'Saved to your gallery'
          // Said plainly rather than letting it be discovered on playback.
          : 'Saved to your gallery, without sound';
    } on SaveException {
      rethrow;
    } catch (_) {
      throw SaveException("Couldn't save that video.");
    } finally {
      for (final file in [videoFile, audioFile, outputFile]) {
        if (await file.exists()) await file.delete();
      }
    }
  }

  Future<void> _download(String url, File into) async {
    final http.Response res;
    try {
      res = await _http.get(Uri.parse(url), headers: _headers);
    } catch (_) {
      throw SaveException("Couldn't download it — check your connection.");
    }
    if (res.statusCode != 200) {
      throw SaveException('The server answered HTTP ${res.statusCode}.');
    }
    if (res.bodyBytes.length > maxBytes) {
      throw SaveException('That file is too large to save.');
    }
    await into.writeAsBytes(res.bodyBytes);
  }

  static const _headers = {'User-Agent': 'Omni/1.0 (+feed reader)'};

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
