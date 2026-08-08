import 'package:xml/xml.dart';

/// The separate files Reddit splits a video into.
///
/// `v.redd.it` serves adaptive streams, which means the picture and the
/// sound are different files. Playing the video file alone is why a saved
/// Reddit video is silent — the audio was never in it.
class DashTracks {
  const DashTracks({required this.videoUrl, this.audioUrl});

  final String videoUrl;

  /// Null when the video genuinely has no sound, which is the case for
  /// every Reddit-converted GIF.
  final String? audioUrl;

  bool get hasAudio => audioUrl != null;
}

/// Picks the best video track, and its audio, out of a DASH manifest.
///
/// Reddit's URL naming has changed over the years — `DASH_720.mp4`,
/// `DASH_2_4_M`, and others — so the manifest is parsed rather than the
/// filenames guessed. Returns null when the document isn't a manifest or
/// carries no video, which callers treat as "save the file we already had".
DashTracks? parseDashManifest(String xml, Uri manifestUri) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(xml);
  } on XmlException {
    return null;
  }

  final sets = document.findAllElements('AdaptationSet');
  if (sets.isEmpty) return null;

  String? bestVideo;
  var bestScore = -1;
  String? audio;

  for (final set in sets) {
    final kind = _kindOf(set);
    if (kind == null) continue;

    for (final representation in set.findAllElements('Representation')) {
      final path = representation.getElement('BaseURL')?.innerText.trim();
      if (path == null || path.isEmpty) continue;

      // BaseURL is relative to wherever the manifest lives.
      final url = manifestUri.resolve(path).toString();

      if (kind == _TrackKind.audio) {
        // Any audio track will do; they differ only in bitrate.
        audio ??= url;
        continue;
      }

      // Prefer the largest picture, falling back to bandwidth when a
      // representation doesn't declare its height.
      final score = int.tryParse(representation.getAttribute('height') ?? '') ??
          int.tryParse(representation.getAttribute('bandwidth') ?? '') ??
          0;
      if (score > bestScore) {
        bestScore = score;
        bestVideo = url;
      }
    }
  }

  return bestVideo == null
      ? null
      : DashTracks(videoUrl: bestVideo, audioUrl: audio);
}

enum _TrackKind { video, audio }

/// Manifests label tracks with `contentType`, `mimeType`, or neither — in
/// which case the representations inside carry the mime type instead.
_TrackKind? _kindOf(XmlElement set) {
  final labels = [
    set.getAttribute('contentType'),
    set.getAttribute('mimeType'),
    for (final r in set.findAllElements('Representation'))
      r.getAttribute('mimeType'),
  ].whereType<String>().map((s) => s.toLowerCase());

  for (final label in labels) {
    if (label.contains('video')) return _TrackKind.video;
    if (label.contains('audio')) return _TrackKind.audio;
  }
  return null;
}

/// Where the manifest for a `v.redd.it` video lives, given any file under
/// it. Returns null for anything that isn't Reddit-hosted video.
String? dashManifestUrlFor(String mediaUrl) {
  final uri = Uri.tryParse(mediaUrl);
  if (uri == null || !uri.host.endsWith('v.redd.it')) return null;

  final id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
  if (id == null || id.isEmpty) return null;

  return 'https://${uri.host}/$id/DASHPlaylist.mpd';
}
