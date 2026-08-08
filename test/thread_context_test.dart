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

FeedItem item(Network network, String nativeId) => FeedItem(
      id: 's:1',
      sourceId: 's',
      network: network,
      author: 'a',
      nativeId: nativeId,
      createdAt: DateTime.utc(2026, 8, 1),
    );

Map<String, dynamic> bskyPost(String cid, String text, {List? labels}) => {
      'uri': 'at://did/app.bsky.feed.post/$cid',
      'cid': cid,
      'author': {'handle': 'a.bsky.social', 'displayName': 'A'},
      'record': {'text': text, 'createdAt': '2026-08-01T10:00:00.000Z'},
      if (labels != null) 'labels': labels,
    };

void main() {
  group('thread ancestors', () {
    test('Mastodon keeps the ancestors it used to discard', () async {
      Map<String, dynamic> status(String id, String? parent, String body) => {
            'id': id,
            'in_reply_to_id': parent,
            'created_at': '2026-08-01T10:00:00.000Z',
            'content': '<p>$body</p>',
            'account': {'display_name': 'A', 'acct': 'a', 'username': 'a'},
            'media_attachments': [],
          };

      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'ancestors': [
              status('root', null, 'the original question'),
              status('mid', 'root', 'an intermediate reply'),
            ],
            'descendants': [status('child', '1', 'a reply to this')],
          }),
          200));

      final thread = await SourceClient.forSource(
        src(Network.mastodon, {'instance': 'mastodon.social'}),
        client,
      ).fetchThread(item(Network.mastodon, '1'));

      // Oldest first, so the conversation reads top to bottom.
      expect(thread.ancestors.map((a) => a.text),
          ['the original question', 'an intermediate reply']);
      expect(thread.replies.single.item.text, 'a reply to this');
    });

    test('Bluesky walks the parent chain and reverses it', () async {
      final client = MockClient((req) async {
        expect(req.url.queryParameters['parentHeight'], isNotNull);
        return http.Response(
            jsonEncode({
              'thread': {
                'post': bskyPost('self', 'this post'),
                'parent': {
                  'post': bskyPost('p1', 'direct parent'),
                  'parent': {'post': bskyPost('p2', 'grandparent')},
                },
                'replies': [
                  {'post': bskyPost('r1', 'a reply')},
                ],
              },
            }),
            200);
      });

      final thread = await SourceClient.forSource(
        src(Network.bluesky, {'handle': 'a.bsky.social'}),
        client,
      ).fetchThread(item(Network.bluesky, 'at://did/app.bsky.feed.post/self'));

      expect(thread.ancestors.map((a) => a.text),
          ['grandparent', 'direct parent']);
      expect(thread.replies.single.item.text, 'a reply');
    });

    test('a root post has no ancestors', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'thread': {
              'post': bskyPost('self', 'root'),
              'replies': [],
            },
          }),
          200));

      final thread = await SourceClient.forSource(
        src(Network.bluesky, {'handle': 'a.bsky.social'}),
        client,
      ).fetchThread(item(Network.bluesky, 'at://did/app.bsky.feed.post/self'));

      expect(thread.ancestors, isEmpty);
      expect(thread.isEmpty, isTrue);
    });
  });

  group('Bluesky moderation labels', () {
    Future<FeedItem> fetchWithLabels(List? labels) async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'feed': [
              {'post': bskyPost('c1', 'a post', labels: labels)},
            ],
          }),
          200));

      final items = await SourceClient.forSource(
        src(Network.bluesky, {'handle': 'a.bsky.social'}),
        client,
      ).fetchLatest();
      return items.single;
    }

    test('an adult label hides the post until revealed', () async {
      final post = await fetchWithLabels([
        {'val': 'porn'},
      ]);

      expect(post.sensitive, isTrue);
      expect(post.contentWarning, 'Adult content');
      expect(post.needsReveal, isTrue);
    });

    test('graphic media gets its own wording', () async {
      final post = await fetchWithLabels([
        {'val': 'graphic-media'},
      ]);
      expect(post.contentWarning, 'Graphic media');
    });

    test('an unrelated label does not hide anything', () async {
      final post = await fetchWithLabels([
        {'val': 'spam'},
      ]);

      expect(post.sensitive, isFalse);
      expect(post.needsReveal, isFalse);
    });

    test('no labels at all is the common case', () async {
      final post = await fetchWithLabels(null);
      expect(post.needsReveal, isFalse);
    });
  });

  group('alt text', () {
    test('Bluesky carries the author\'s image description', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'feed': [
              {
                'post': {
                  ...bskyPost('c1', 'look at this'),
                  'embed': {
                    'images': [
                      {'thumb': 'https://cdn/1.jpg', 'alt': 'a red bicycle'},
                      {'thumb': 'https://cdn/2.jpg'},
                    ],
                  },
                },
              },
            ],
          }),
          200));

      final items = await SourceClient.forSource(
        src(Network.bluesky, {'handle': 'a.bsky.social'}),
        client,
      ).fetchLatest();

      expect(items.single.media, hasLength(2));
      expect(items.single.media.first.alt, 'a red bicycle');
      expect(items.single.media.first.hasAlt, isTrue);
      expect(items.single.media.last.hasAlt, isFalse);
      expect(items.single.imageUrls, ['https://cdn/1.jpg', 'https://cdn/2.jpg']);
    });

    test('Mastodon carries its media description', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode([
            {
              'id': '1',
              'created_at': '2026-08-05T12:00:00.000Z',
              'content': '<p>hi</p>',
              'account': {'display_name': 'A', 'acct': 'a', 'username': 'a'},
              'media_attachments': [
                {
                  'type': 'image',
                  'preview_url': 'https://cdn/m.jpg',
                  'description': 'a photo of a cat',
                },
              ],
            },
          ]),
          200));

      final items = await SourceClient.forSource(
        src(Network.mastodon, {'instance': 'mastodon.social'}),
        client,
      ).fetchLatest();

      expect(items.single.media.single.alt, 'a photo of a cat');
    });
  });

  group('X home timeline', () {
    test('refuses without a signed-in account, and says why', () async {
      final client = MockClient((_) async => http.Response('{}', 200));

      expect(
        SourceClient.forSource(
          FeedSource(
            id: 't',
            network: Network.twitter,
            displayName: 'X home',
            params: {'mode': 'guest', 'feed': 'home'},
          ),
          client,
        ).fetchLatest(),
        throwsA(predicate((e) =>
            e is SourceFetchException &&
            e.message.contains('signed-in account'))),
      );
    });
  });
}
