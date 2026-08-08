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

Future<FeedItem> firstFrom(Network network, Map<String, String> params,
    Object body) async {
  final client = MockClient(
      (_) async => http.Response(body is String ? body : jsonEncode(body), 200));
  final items =
      await SourceClient.forSource(src(network, params), client).fetchLatest();
  return items.single;
}

Map<String, dynamic> bskyFeed(Map<String, dynamic> embed) => {
      'feed': [
        {
          'post': {
            'uri': 'at://did/app.bsky.feed.post/1',
            'cid': 'c1',
            'author': {'handle': 'a.bsky.social', 'displayName': 'A'},
            'record': {
              'text': 'my commentary',
              'createdAt': '2026-08-05T10:00:00.000Z',
            },
            'embed': embed,
          },
        },
      ],
    };

void main() {
  group('Bluesky quotes', () {
    test('carries the quoted post rather than bare commentary', () async {
      final item = await firstFrom(
        Network.bluesky,
        {'handle': 'a.bsky.social'},
        bskyFeed({
          'record': {
            'uri': 'at://did/app.bsky.feed.post/q',
            'cid': 'cq',
            'author': {'handle': 'b.bsky.social', 'displayName': 'B'},
            'value': {
              'text': 'the original claim',
              'createdAt': '2026-08-04T10:00:00.000Z',
            },
          },
        }),
      );

      expect(item.text, 'my commentary');
      expect(item.quoted, isNotNull);
      expect(item.quoted!.text, 'the original claim');
      expect(item.quoted!.handle, '@b.bsky.social');
      expect(item.quoted!.url,
          'https://bsky.app/profile/b.bsky.social/post/q');
    });

    test('finds the quote when the post also has media', () async {
      final item = await firstFrom(
        Network.bluesky,
        {'handle': 'a.bsky.social'},
        bskyFeed({
          'record': {
            'record': {
              'uri': 'at://did/app.bsky.feed.post/q',
              'cid': 'cq',
              'author': {'handle': 'b.bsky.social', 'displayName': 'B'},
              'value': {
                'text': 'quoted with media alongside',
                'createdAt': '2026-08-04T10:00:00.000Z',
              },
            },
          },
          'media': {
            'images': [
              {'thumb': 'https://cdn/1.jpg', 'alt': 'a chart'},
            ],
          },
        }),
      );

      expect(item.quoted!.text, 'quoted with media alongside');
      expect(item.media.single.alt, 'a chart');
    });

    test('a deleted quote is omitted rather than shown as a blank', () async {
      final item = await firstFrom(
        Network.bluesky,
        {'handle': 'a.bsky.social'},
        bskyFeed({
          'record': {r'$type': 'app.bsky.embed.record#viewNotFound'},
        }),
      );

      expect(item.quoted, isNull);
    });

    test('reads an external link embed as a card', () async {
      final item = await firstFrom(
        Network.bluesky,
        {'handle': 'a.bsky.social'},
        bskyFeed({
          'external': {
            'uri': 'https://example.com/article',
            'title': 'An article',
            'description': 'What it says',
            'thumb': 'https://cdn/thumb.jpg',
          },
        }),
      );

      expect(item.linkCard!.url, 'https://example.com/article');
      expect(item.linkCard!.title, 'An article');
      expect(item.linkCard!.imageUrl, 'https://cdn/thumb.jpg');
    });
  });

  group('Mastodon polls', () {
    test('carries options and vote shares', () async {
      final item = await firstFrom(
        Network.mastodon,
        {'instance': 'mastodon.social'},
        [
          {
            'id': '1',
            'created_at': '2026-08-05T12:00:00.000Z',
            'content': '<p>Which one?</p>',
            'account': {'display_name': 'A', 'acct': 'a', 'username': 'a'},
            'media_attachments': [],
            'poll': {
              'votes_count': 10,
              'expired': false,
              'expires_at': '2026-08-09T12:00:00.000Z',
              'options': [
                {'title': 'First', 'votes_count': 7},
                {'title': 'Second', 'votes_count': 3},
              ],
            },
          },
        ],
      );

      expect(item.poll, isNotNull);
      expect(item.poll!.options.map((o) => o.title), ['First', 'Second']);
      expect(item.poll!.totalVotes, 10);
      expect(item.poll!.shareOf(item.poll!.options.first), 0.7);
      expect(item.poll!.expired, isFalse);
    });

    test('a poll with no votes yet divides by zero safely', () {
      const poll = Poll(
        options: [PollOption(title: 'A'), PollOption(title: 'B')],
      );
      expect(poll.shareOf(poll.options.first), 0);
    });

    test('reads a preview card', () async {
      final item = await firstFrom(
        Network.mastodon,
        {'instance': 'mastodon.social'},
        [
          {
            'id': '1',
            'created_at': '2026-08-05T12:00:00.000Z',
            'content': '<p>look</p>',
            'account': {'display_name': 'A', 'acct': 'a', 'username': 'a'},
            'media_attachments': [],
            'card': {
              'url': 'https://example.com/x',
              'title': 'Headline',
              'description': 'Standfirst',
              'image': 'https://cdn/card.jpg',
            },
          },
        ],
      );

      expect(item.linkCard!.title, 'Headline');
      expect(item.linkCard!.description, 'Standfirst');
    });
  });

  group('Reddit', () {
    Map<String, dynamic> listing(Map<String, dynamic> data) => {
          'data': {
            'children': [
              {
                'data': {
                  'name': 't3_a',
                  'title': 'A post',
                  'author': 'someone',
                  'subreddit': 'law',
                  'permalink': '/r/law/a/',
                  'created_utc': 1785924000,
                  ...data,
                },
              },
            ],
          },
        };

    test('reads every image of a gallery, not just one', () async {
      final item = await firstFrom(Network.reddit, {'subreddit': 'law'},
          listing({
            'gallery_data': {
              'items': [
                {'media_id': 'm1', 'caption': 'first shot'},
                {'media_id': 'm2'},
              ],
            },
            'media_metadata': {
              'm1': {'s': {'u': 'https://i.redd.it/1.jpg?w=1&amp;s=x'}},
              'm2': {'s': {'u': 'https://i.redd.it/2.jpg'}},
            },
          }));

      expect(item.media, hasLength(2));
      // The &amp; would 404 if it survived.
      expect(item.media.first.url, 'https://i.redd.it/1.jpg?w=1&s=x');
      expect(item.media.first.alt, 'first shot');
    });

    test('takes a crosspost\'s content from the original', () async {
      final item = await firstFrom(Network.reddit, {'subreddit': 'law'},
          listing({
            'crosspost_parent_list': [
              {
                'selftext': 'the actual body',
                'subreddit': 'news',
                'preview': {
                  'images': [
                    {'source': {'url': 'https://preview.redd.it/x.png'}},
                  ],
                },
              },
            ],
          }));

      // Without this a crosspost renders as an empty post.
      expect(item.fullText, 'the actual body');
      expect(item.imageUrls, ['https://preview.redd.it/x.png']);
      expect(item.repostedBy, contains('r/news'));
    });

    test('carries flair', () async {
      final item = await firstFrom(Network.reddit, {'subreddit': 'law'},
          listing({'link_flair_text': 'Analysis'}));
      expect(item.flair, 'Analysis');
    });

    test('cards an outbound link but not reddit-hosted media', () async {
      final external = await firstFrom(Network.reddit, {'subreddit': 'law'},
          listing({'url_overridden_by_dest': 'https://nytimes.com/article'}));
      expect(external.linkCard!.url, 'https://nytimes.com/article');
      expect(external.linkCard!.title, 'nytimes.com');

      final selfHosted = await firstFrom(Network.reddit, {'subreddit': 'law'},
          listing({'url_overridden_by_dest': 'https://i.redd.it/x.png'}));
      expect(selfHosted.linkCard, isNull);
    });
  });

  group('serialization', () {
    test('a saved post keeps its quote, poll, card and flair', () {
      final item = FeedItem(
        id: 'x',
        sourceId: 's',
        network: Network.bluesky,
        author: 'A',
        text: 'commentary',
        flair: 'Analysis',
        linkCard: const LinkCard(url: 'https://e.com', title: 'T'),
        poll: const Poll(
          options: [PollOption(title: 'Yes', votes: 3)],
          totalVotes: 3,
        ),
        quoted: FeedItem(
          id: 'q',
          sourceId: 's',
          network: Network.bluesky,
          author: 'B',
          text: 'original',
          createdAt: DateTime.utc(2026, 8, 4),
        ),
        createdAt: DateTime.utc(2026, 8, 5),
      );

      final restored = FeedItem.fromJson(item.toJson());
      expect(restored.quoted!.text, 'original');
      expect(restored.linkCard!.title, 'T');
      expect(restored.poll!.options.single.votes, 3);
      expect(restored.flair, 'Analysis');
    });
  });
}
