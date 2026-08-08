import 'package:flutter/services.dart';

/// Joins a video-only file and an audio-only file into one playable MP4.
///
/// The work happens in Android's own `MediaMuxer` — a container rewrite
/// rather than a re-encode, so it costs seconds and no quality. Dart only
/// hands over three paths.
class MediaRemuxer {
  const MediaRemuxer([this.channel = const MethodChannel('dev.omni/media')]);

  final MethodChannel channel;

  /// Returns whether [outputPath] was written. False rather than throwing:
  /// callers fall back to saving the silent video, which is worth more than
  /// an error.
  Future<bool> remux({
    required String videoPath,
    required String audioPath,
    required String outputPath,
  }) async {
    try {
      final joined = await channel.invokeMethod<bool>('remux', {
        'videoPath': videoPath,
        'audioPath': audioPath,
        'outputPath': outputPath,
      });
      return joined ?? false;
    } on MissingPluginException {
      // No platform side — a unit test, or a build without the channel.
      return false;
    } on PlatformException {
      // A track the muxer wouldn't accept, or a truncated download.
      return false;
    }
  }
}
