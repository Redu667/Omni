import 'package:flutter_test/flutter_test.dart';
import 'package:omni/services/reddit_dash.dart';

final _manifestUri = Uri.parse('https://v.redd.it/abc123/DASHPlaylist.mpd');

String manifest(String body) => '''<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static">
  <Period>$body</Period>
</MPD>''';

const _typicalReddit = '''
    <AdaptationSet contentType="video">
      <Representation id="1" height="360" bandwidth="400000">
        <BaseURL>DASH_360.mp4</BaseURL>
      </Representation>
      <Representation id="2" height="720" bandwidth="1200000">
        <BaseURL>DASH_720.mp4</BaseURL>
      </Representation>
    </AdaptationSet>
    <AdaptationSet contentType="audio">
      <Representation id="3" bandwidth="128000">
        <BaseURL>DASH_audio.mp4</BaseURL>
      </Representation>
    </AdaptationSet>''';

void main() {
  group('finding the tracks', () {
    test('takes the largest picture and its audio', () {
      final tracks = parseDashManifest(manifest(_typicalReddit), _manifestUri)!;

      expect(tracks.videoUrl, 'https://v.redd.it/abc123/DASH_720.mp4');
      expect(tracks.audioUrl, 'https://v.redd.it/abc123/DASH_audio.mp4');
      expect(tracks.hasAudio, isTrue);
    });

    test('resolves BaseURL against where the manifest lives', () {
      final tracks = parseDashManifest(manifest(_typicalReddit), _manifestUri)!;
      // Relative, so a naive join would produce .../DASHPlaylist.mpdDASH_720.mp4
      expect(tracks.videoUrl, isNot(contains('DASHPlaylist')));
    });

    test('an absolute BaseURL is left alone', () {
      final tracks = parseDashManifest(
          manifest('''
    <AdaptationSet contentType="video">
      <Representation height="720">
        <BaseURL>https://cdn.example/v.mp4</BaseURL>
      </Representation>
    </AdaptationSet>'''),
          _manifestUri)!;

      expect(tracks.videoUrl, 'https://cdn.example/v.mp4');
    });

    test('labels the tracks by mimeType when contentType is absent', () {
      final tracks = parseDashManifest(
          manifest('''
    <AdaptationSet mimeType="video/mp4">
      <Representation height="480"><BaseURL>v.mp4</BaseURL></Representation>
    </AdaptationSet>
    <AdaptationSet mimeType="audio/mp4">
      <Representation><BaseURL>a.mp4</BaseURL></Representation>
    </AdaptationSet>'''),
          _manifestUri)!;

      expect(tracks.videoUrl, endsWith('/v.mp4'));
      expect(tracks.audioUrl, endsWith('/a.mp4'));
    });

    test('falls back to the mimeType on the representation', () {
      final tracks = parseDashManifest(
          manifest('''
    <AdaptationSet>
      <Representation mimeType="video/mp4" height="720">
        <BaseURL>v.mp4</BaseURL>
      </Representation>
    </AdaptationSet>'''),
          _manifestUri)!;

      expect(tracks.videoUrl, endsWith('/v.mp4'));
    });

    test('ranks by bandwidth when heights are missing', () {
      final tracks = parseDashManifest(
          manifest('''
    <AdaptationSet contentType="video">
      <Representation bandwidth="400000"><BaseURL>low.mp4</BaseURL></Representation>
      <Representation bandwidth="2400000"><BaseURL>high.mp4</BaseURL></Representation>
    </AdaptationSet>'''),
          _manifestUri)!;

      expect(tracks.videoUrl, endsWith('/high.mp4'));
    });

    test('a video with no audio track reports none', () {
      final tracks = parseDashManifest(
          manifest('''
    <AdaptationSet contentType="video">
      <Representation height="480"><BaseURL>v.mp4</BaseURL></Representation>
    </AdaptationSet>'''),
          _manifestUri)!;

      // Every Reddit-converted GIF looks like this; silence is correct.
      expect(tracks.hasAudio, isFalse);
      expect(tracks.audioUrl, isNull);
    });
  });

  group('declining', () {
    test('on something that is not a manifest', () {
      expect(parseDashManifest('<html><body>nope</body></html>', _manifestUri),
          isNull);
      expect(parseDashManifest('not xml at all {', _manifestUri), isNull);
    });

    test('on a manifest with audio but no video', () {
      final tracks = parseDashManifest(
          manifest('''
    <AdaptationSet contentType="audio">
      <Representation><BaseURL>a.mp4</BaseURL></Representation>
    </AdaptationSet>'''),
          _manifestUri);

      expect(tracks, isNull);
    });

    test('on a representation with no BaseURL', () {
      final tracks = parseDashManifest(
          manifest('''
    <AdaptationSet contentType="video">
      <Representation height="720"/>
    </AdaptationSet>'''),
          _manifestUri);

      expect(tracks, isNull);
    });
  });

  group('locating the manifest', () {
    test('from any file under the video', () {
      for (final url in [
        'https://v.redd.it/abc123/HLSPlaylist.m3u8',
        'https://v.redd.it/abc123/DASH_720.mp4',
        'https://v.redd.it/abc123/DASHPlaylist.mpd',
      ]) {
        expect(dashManifestUrlFor(url),
            'https://v.redd.it/abc123/DASHPlaylist.mpd',
            reason: url);
      }
    });

    test('not for anything that is not Reddit video', () {
      for (final url in [
        'https://video.bsky.app/1/playlist.m3u8',
        'https://video.twimg.com/high.mp4',
        'https://preview.redd.it/a.png',
        'https://www.reddit.com/r/law',
        'not a url at all',
      ]) {
        expect(dashManifestUrlFor(url), isNull, reason: url);
      }
    });
  });
}
