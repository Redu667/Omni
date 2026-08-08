import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_item.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/source_client.dart';

FeedSource src(Network network, Map<String, String> params) =>
    FeedSource(id: 's', network: network, displayName: 'T', params: params);

Future<FeedItem> firstFrom(
    Network network, Map<String, String> params, Object body) async {
  final client = MockClient(
      (_) async => http.Response.bytes(utf8.encode(jsonEncode(body)), 200));
  return (await SourceClient.forSource(src(network, params), client)
          .fetchLatest())
      .single;
}

void main() {
  group('Mastodon', () {
    Map<String, dynamic> status(List<Map<String, dynamic>> attachments) => {
          'id': '1',
          'created_at': '2026-08-05T10:00:00.000Z',
          'content': '<p>look</p>',
          'account': {'display_name': 'A', 'acct': 'a', 'username': 'a'},
          'media_attachments': attachments,
        };

    test('a video carries its stream, poster and duration', () async {
      final item = await firstFrom(
          Network.mastodon,
          {'instance': 'mastodon.social'},
          [
            status([
              {
                'type': 'video',
                'url': 'https://m.example/v.mp4',
                'preview_url': 'https://m.example/v.png',
                'description': 'a cat',
                'meta': {
                  'original': {'duration': 12.4},
                },
              },
            ]),
          ]);

      final media = item.media.single;
      expect(media.kind, MediaKind.video);
      expect(media.url, 'https://m.example/v.mp4');
      expect(media.thumbnailUrl, 'https://m.example/v.png');
      expect(media.alt, 'a cat');
      expect(media.durationSeconds, 12);
      expect(media.kind.isPlayable, isTrue);
    });

    test('a gifv is a gif, not a video', () async {
      final item = await firstFrom(
          Network.mastodon,
          {'instance': 'mastodon.social'},
          [
            status([
              {
                'type': 'gifv',
                'url': 'https://m.example/g.mp4',
                'preview_url': 'https://m.example/g.png',
              },
            ]),
          ]);

      expect(item.media.single.kind, MediaKind.gif);
    });

    test('images are unaffected', () async {
      final item = await firstFrom(
          Network.mastodon,
          {'instance': 'mastodon.social'},
          [
            status([
              {
                'type': 'image',
                'url': 'https://m.example/full.png',
                'preview_url': 'https://m.example/small.png',
              },
            ]),
          ]);

      expect(item.media.single.kind, MediaKind.image);
      expect(item.media.single.url, 'https://m.example/small.png');
      expect(item.media.single.kind.isPlayable, isFalse);
    });

    test('audio is still skipped rather than shown as a broken image',
        () async {
      final item = await firstFrom(
          Network.mastodon,
          {'instance': 'mastodon.social'},
          [
            status([
              {'type': 'audio', 'url': 'https://m.example/a.mp3'},
            ]),
          ]);

      expect(item.media, isEmpty);
    });
  });

  group('Bluesky', () {
    Map<String, dynamic> feed(Map<String, dynamic> embed) => {
          'feed': [
            {
              'post': {
                'uri': 'at://did/app.bsky.feed.post/1',
                'cid': 'c1',
                'author': {'handle': 'a.bsky.social', 'displayName': 'A'},
                'record': {
                  'text': 'look',
                  'createdAt': '2026-08-05T10:00:00.000Z',
                },
                'embed': embed,
              },
            },
          ],
        };

    test('a video embed becomes a playable HLS item', () async {
      final item =
          await firstFrom(Network.bluesky, {'handle': 'a.bsky.social'}, feed({
        r'$type': 'app.bsky.embed.video#view',
        'playlist': 'https://video.bsky.app/1/playlist.m3u8',
        'thumbnail': 'https://video.bsky.app/1/thumb.jpg',
        'alt': 'a dog',
      }));

      final media = item.media.single;
      expect(media.kind, MediaKind.video);
      expect(media.url, endsWith('playlist.m3u8'));
      expect(media.thumbnailUrl, endsWith('thumb.jpg'));
      expect(media.alt, 'a dog');
    });

    test('a video nested under recordWithMedia is still found', () async {
      final item =
          await firstFrom(Network.bluesky, {'handle': 'a.bsky.social'}, feed({
        r'$type': 'app.bsky.embed.recordWithMedia#view',
        'media': {
          r'$type': 'app.bsky.embed.video#view',
          'playlist': 'https://video.bsky.app/2/playlist.m3u8',
        },
      }));

      expect(item.media.single.kind, MediaKind.video);
    });

    test('an embed with no playlist yields nothing', () async {
      final item =
          await firstFrom(Network.bluesky, {'handle': 'a.bsky.social'}, feed({
        r'$type': 'app.bsky.embed.video#view',
        'thumbnail': 'https://video.bsky.app/3/thumb.jpg',
      }));

      expect(item.media, isEmpty);
    });
  });

  group('Reddit', () {
    Map<String, dynamic> listing(Map<String, dynamic> post) => {
          'data': {
            'children': [
              {
                'data': {
                  'name': 't3_1',
                  'title': 'a clip',
                  'author': 'someone',
                  'permalink': '/r/videos/comments/1/a_clip/',
                  'subreddit': 'videos',
                  'created_utc': 1785924000,
                  ...post,
                },
              },
            ],
            'after': null,
          },
        };

    test('prefers the HLS stream, which is the one with sound', () async {
      final item = await firstFrom(
          Network.reddit,
          {'subreddit': 'videos'},
          listing({
            'secure_media': {
              'reddit_video': {
                'hls_url': 'https://v.redd.it/abc/HLSPlaylist.m3u8',
                'fallback_url': 'https://v.redd.it/abc/DASH_720.mp4',
                'duration': 33,
              },
            },
            'preview': {
              'images': [
                {
                  'source': {'url': 'https://preview.redd.it/a.png?s=1&amp;t=2'},
                },
              ],
            },
          }));

      final media = item.media.single;
      expect(media.kind, MediaKind.video);
      expect(media.url, contains('HLSPlaylist'));
      expect(media.durationSeconds, 33);
      // The escaped ampersand would 404 if left as-is.
      expect(media.thumbnailUrl, 'https://preview.redd.it/a.png?s=1&t=2');
    });

    test('falls back to the video-only URL when there is no HLS', () async {
      final item = await firstFrom(
          Network.reddit,
          {'subreddit': 'videos'},
          listing({
            'media': {
              'reddit_video': {
                'fallback_url': 'https://v.redd.it/abc/DASH_720.mp4',
                'is_gif': true,
              },
            },
          }));

      expect(item.media.single.url, endsWith('DASH_720.mp4'));
      // A converted GIF has no audio to lose.
      expect(item.media.single.kind, MediaKind.gif);
    });

    test('the video wins over the preview still', () async {
      final item = await firstFrom(
          Network.reddit,
          {'subreddit': 'videos'},
          listing({
            'preview': {
              'reddit_video_preview': {
                'hls_url': 'https://v.redd.it/xyz/HLSPlaylist.m3u8',
              },
              'images': [
                {
                  'source': {'url': 'https://preview.redd.it/x.png'},
                },
              ],
            },
          }));

      expect(item.media, hasLength(1));
      expect(item.media.single.kind, MediaKind.video);
    });

    test('an ordinary image post is untouched', () async {
      final item = await firstFrom(
          Network.reddit,
          {'subreddit': 'pics'},
          listing({
            'preview': {
              'images': [
                {
                  'source': {'url': 'https://preview.redd.it/p.png'},
                },
              ],
            },
          }));

      expect(item.media.single.kind, MediaKind.image);
    });
  });

  group('saved posts', () {
    test('video survives a round-trip through JSON', () {
      final item = FeedItem(
        id: 's:1',
        sourceId: 's',
        network: Network.mastodon,
        author: 'A',
        media: const [
          MediaItem(
            url: 'https://e/v.mp4',
            kind: MediaKind.video,
            thumbnailUrl: 'https://e/v.png',
            durationSeconds: 30,
            alt: 'a clip',
          ),
        ],
        createdAt: DateTime.utc(2026, 8, 1),
      );

      final media = FeedItem.fromJson(item.toJson()).media.single;
      expect(media.kind, MediaKind.video);
      expect(media.thumbnailUrl, 'https://e/v.png');
      expect(media.durationSeconds, 30);
      expect(media.alt, 'a clip');
    });

    test('a post saved before video existed loads as an image', () {
      final media = MediaItem.fromJson({'url': 'https://e/a.png'});
      expect(media.kind, MediaKind.image);
      expect(media.previewUrl, 'https://e/a.png');
    });
  });
}
