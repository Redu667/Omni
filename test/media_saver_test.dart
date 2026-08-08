import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:http/testing.dart';
import 'package:omni/models/feed_item.dart';
import 'package:omni/services/media_remuxer.dart';
import 'package:omni/services/media_saver.dart';

/// Records what the gallery was asked to store, standing in for the plugin.
class Gallery {
  final images = <({List<int> bytes, String name})>[];
  final videos = <String>[];
  bool granted = true;
  int accessRequests = 0;
}

/// Stands in for Android's muxer, which unit tests can't reach.
class FakeRemuxer extends MediaRemuxer {
  FakeRemuxer({this.succeeds = true}) : super(const MethodChannel('test'));

  final bool succeeds;
  final calls = <({String video, String audio, String output})>[];

  @override
  Future<bool> remux({
    required String videoPath,
    required String audioPath,
    required String outputPath,
  }) async {
    calls.add((video: videoPath, audio: audioPath, output: outputPath));
    if (succeeds) await File(outputPath).writeAsBytes([9, 9, 9]);
    return succeeds;
  }
}

MediaSaver saverWith(
  Gallery gallery, {
  required http.Client client,
  Directory? temp,
  int maxBytes = 200 * 1024 * 1024,
  MediaRemuxer? remuxer,
}) =>
    MediaSaver(
      httpClient: client,
      maxBytes: maxBytes,
      remuxer: remuxer,
      tempDirectory: () async => temp ?? Directory.systemTemp,
      saveImage: (bytes, name) async =>
          gallery.images.add((bytes: bytes, name: name)),
      saveVideo: (path) async => gallery.videos.add(path),
      hasAccess: () async => gallery.granted,
      requestAccess: () async {
        gallery.accessRequests++;
        return gallery.granted;
      },
    );

http.Client serving(List<int> bytes, {int status = 200}) =>
    MockClient((_) async => http.Response.bytes(bytes, status));

MediaItem image(String url) => MediaItem(url: url);
MediaItem video(String url) => MediaItem(url: url, kind: MediaKind.video);

void main() {
  _redditTests();
  test('an image goes to the gallery as bytes', () async {
    final gallery = Gallery();
    final message = await saverWith(gallery, client: serving([1, 2, 3]))
        .save(image('https://e.example/photos/cat.jpg'));

    expect(message, contains('Saved'));
    expect(gallery.images.single.bytes, [1, 2, 3]);
    // The gallery shows the name, so it says where the file came from.
    expect(gallery.images.single.name, 'omni_cat');
  });

  test('a video goes through a file, which is cleaned up after', () async {
    final gallery = Gallery();
    final temp = await Directory.systemTemp.createTemp('omni_save_test');
    addTearDown(() => temp.delete(recursive: true));

    await saverWith(gallery, client: serving([1, 2, 3]), temp: temp)
        .save(video('https://e.example/clips/clip.mp4'));

    expect(gallery.videos.single, endsWith('omni_clip.mp4'));
    // Keeping a copy in the cache would double what saving costs on disk.
    expect(temp.listSync(), isEmpty);
  });

  test('a video with no extension in the url still gets one', () async {
    final gallery = Gallery();
    final temp = await Directory.systemTemp.createTemp('omni_save_test');
    addTearDown(() => temp.delete(recursive: true));

    await saverWith(gallery, client: serving([1]), temp: temp)
        .save(video('https://e.example/watch'));

    expect(gallery.videos.single, endsWith('.mp4'));
  });

  group('refuses honestly', () {
    test('a streamed playlist with no whole-file equivalent', () async {
      final gallery = Gallery();

      // Bluesky's HLS is segments and nothing else. Reddit is handled
      // separately, because there the parts do exist as files.
      await expectLater(
        saverWith(gallery, client: serving([1]))
            .save(video('https://video.bsky.app/1/playlist.m3u8')),
        throwsA(isA<SaveException>()
            .having((e) => e.message, 'message', contains('streamed'))),
      );
      expect(gallery.videos, isEmpty);
    });

    test('when permission is refused', () async {
      final gallery = Gallery()..granted = false;

      await expectLater(
        saverWith(gallery, client: serving([1])).save(image('https://e/a.jpg')),
        throwsA(isA<SaveException>()
            .having((e) => e.message, 'message', contains('permission'))),
      );
      expect(gallery.accessRequests, 1);
      expect(gallery.images, isEmpty);
    });

    test('a file too large to be worth downloading', () async {
      final gallery = Gallery();

      await expectLater(
        saverWith(gallery,
                client: serving(List.filled(100, 0)), maxBytes: 10)
            .save(image('https://e/a.jpg')),
        throwsA(isA<SaveException>()
            .having((e) => e.message, 'message', contains('too large'))),
      );
    });

    test('a server that says no', () async {
      final gallery = Gallery();

      await expectLater(
        saverWith(gallery, client: serving([], status: 403))
            .save(image('https://e/a.jpg')),
        throwsA(isA<SaveException>()
            .having((e) => e.message, 'message', contains('403'))),
      );
    });

    test('a connection that never opened', () async {
      final gallery = Gallery();
      final client = MockClient((_) async => throw const SocketException('x'));

      await expectLater(
        saverWith(gallery, client: client).save(image('https://e/a.jpg')),
        throwsA(isA<SaveException>()
            .having((e) => e.message, 'message', contains('connection'))),
      );
    });
  });

  group('naming', () {
    test('strips characters a filesystem would object to', () async {
      final gallery = Gallery();
      await saverWith(gallery, client: serving([1]))
          .save(image('https://e/a/we%20ird!name.png'));

      expect(gallery.images.single.name, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    });

    test('falls back when the url has no filename', () async {
      final gallery = Gallery();
      await saverWith(gallery, client: serving([1])).save(image('https://e'));

      expect(gallery.images.single.name, isNotEmpty);
    });
  });
}

/// Reddit splits a video into separate picture and sound files, so saving
/// one means fetching both and joining them.
void _redditTests() {
  const manifestUrl = 'https://v.redd.it/abc123/DASHPlaylist.mpd';
  const videoUrl = 'https://v.redd.it/abc123/DASH_720.mp4';
  const audioUrl = 'https://v.redd.it/abc123/DASH_audio.mp4';

  String manifest({bool withAudio = true}) => '''<?xml version="1.0"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011"><Period>
  <AdaptationSet contentType="video">
    <Representation height="720"><BaseURL>DASH_720.mp4</BaseURL></Representation>
  </AdaptationSet>
  ${withAudio ? '<AdaptationSet contentType="audio">'
      '<Representation><BaseURL>DASH_audio.mp4</BaseURL></Representation>'
      '</AdaptationSet>' : ''}
</Period></MPD>''';

  ({List<String> fetched, http.Client client}) redditServer({
    bool withAudio = true,
    int videoStatus = 200,
  }) {
    final fetched = <String>[];
    final client = MockClient((req) async {
      final url = req.url.toString();
      fetched.add(url);
      if (url.endsWith('.mpd')) {
        return http.Response(manifest(withAudio: withAudio), 200);
      }
      if (url == videoUrl) {
        return http.Response.bytes([1, 2, 3], videoStatus);
      }
      return http.Response.bytes([4, 5, 6], 200);
    });
    return (fetched: fetched, client: client);
  }

  group('Reddit video', () {
    test('joins the picture and the sound before saving', () async {
      final gallery = Gallery();
      final remuxer = FakeRemuxer();
      final temp = await Directory.systemTemp.createTemp('omni_reddit');
      addTearDown(() => temp.delete(recursive: true));
      final server = redditServer();

      final message = await saverWith(gallery,
              client: server.client, temp: temp, remuxer: remuxer)
          .save(video('https://v.redd.it/abc123/HLSPlaylist.m3u8'));

      // The manifest is consulted rather than the filenames guessed.
      expect(server.fetched, contains(manifestUrl));
      expect(server.fetched, contains(videoUrl));
      expect(server.fetched, contains(audioUrl));
      expect(remuxer.calls, hasLength(1));
      expect(gallery.videos.single, equals(remuxer.calls.single.output));
      expect(message, 'Saved to your gallery');
      // Three temporary files, none of them left behind.
      expect(temp.listSync(), isEmpty);
    });

    test('says so when the video genuinely has no sound', () async {
      final gallery = Gallery();
      final remuxer = FakeRemuxer();
      final temp = await Directory.systemTemp.createTemp('omni_reddit');
      addTearDown(() => temp.delete(recursive: true));

      final message = await saverWith(gallery,
              client: redditServer(withAudio: false).client,
              temp: temp,
              remuxer: remuxer)
          .save(video(manifestUrl));

      // A converted GIF has no audio track; nothing to join.
      expect(remuxer.calls, isEmpty);
      expect(gallery.videos, hasLength(1));
      expect(message, contains('without sound'));
    });

    test('still saves the picture when joining fails', () async {
      final gallery = Gallery();
      final remuxer = FakeRemuxer(succeeds: false);
      final temp = await Directory.systemTemp.createTemp('omni_reddit');
      addTearDown(() => temp.delete(recursive: true));

      final message = await saverWith(gallery,
              client: redditServer().client, temp: temp, remuxer: remuxer)
          .save(video(manifestUrl));

      // A watchable silent clip beats refusing to save anything.
      expect(gallery.videos, hasLength(1));
      expect(message, contains('without sound'));
      expect(temp.listSync(), isEmpty);
    });

    test('reports a refusal from Reddit', () async {
      final gallery = Gallery();
      final temp = await Directory.systemTemp.createTemp('omni_reddit');
      addTearDown(() => temp.delete(recursive: true));

      await expectLater(
        saverWith(gallery,
                client: redditServer(videoStatus: 403).client,
                temp: temp,
                remuxer: FakeRemuxer())
            .save(video(manifestUrl)),
        throwsA(isA<SaveException>()
            .having((e) => e.message, 'message', contains('403'))),
      );
      expect(temp.listSync(), isEmpty);
    });

    test('reports a manifest that is not one', () async {
      final gallery = Gallery();
      final client = MockClient((_) async => http.Response('<html/>', 200));

      await expectLater(
        saverWith(gallery, client: client, remuxer: FakeRemuxer())
            .save(video(manifestUrl)),
        throwsA(isA<SaveException>().having(
            (e) => e.message, 'message', contains("where that video is"))),
      );
    });

    test('a still from Reddit is unaffected', () async {
      final gallery = Gallery();
      final remuxer = FakeRemuxer();

      await saverWith(gallery, client: serving([1]), remuxer: remuxer)
          .save(image('https://preview.redd.it/a.png'));

      expect(remuxer.calls, isEmpty);
      expect(gallery.images, hasLength(1));
    });
  });
}
