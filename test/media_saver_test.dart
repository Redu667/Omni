import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_item.dart';
import 'package:omni/services/media_saver.dart';

/// Records what the gallery was asked to store, standing in for the plugin.
class Gallery {
  final images = <({List<int> bytes, String name})>[];
  final videos = <String>[];
  bool granted = true;
  int accessRequests = 0;
}

MediaSaver saverWith(
  Gallery gallery, {
  required http.Client client,
  Directory? temp,
  int maxBytes = 200 * 1024 * 1024,
}) =>
    MediaSaver(
      httpClient: client,
      maxBytes: maxBytes,
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
    test('a streamed playlist, which is not a file', () async {
      final gallery = Gallery();
      for (final url in [
        'https://video.bsky.app/1/playlist.m3u8',
        'https://v.redd.it/abc/DASHPlaylist.mpd',
      ]) {
        await expectLater(
          saverWith(gallery, client: serving([1])).save(video(url)),
          throwsA(isA<SaveException>()
              .having((e) => e.message, 'message', contains('streamed'))),
          reason: url,
        );
      }
      // Nothing downloaded, because there was nothing worth downloading.
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
