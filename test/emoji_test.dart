import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni/models/feed_item.dart';
import 'package:omni/models/feed_source.dart';
import 'package:omni/models/network.dart';
import 'package:omni/services/source_client.dart';
import 'package:omni/ui/emoji_text.dart';

const _blobcat = 'https://cdn.example/blobcat.png';
const _party = 'https://cdn.example/party.png';
const _emojis = {'blobcat': _blobcat, 'party': _party};

void main() {
  group('splitEmoji', () {
    test('leaves text alone when nothing is declared', () {
      expect(splitEmoji('hello :blobcat:', const {}),
          [const TextChunk('hello :blobcat:')]);
    });

    test('substitutes a declared shortcode', () {
      expect(splitEmoji('hi :blobcat: there', _emojis), [
        const TextChunk('hi '),
        const EmojiRun('blobcat', _blobcat),
        const TextChunk(' there'),
      ]);
    });

    test('leaves undeclared shortcodes as written', () {
      expect(splitEmoji('a :nothere: b', _emojis),
          [const TextChunk('a :nothere: b')]);
    });

    test('does not mangle ordinary colons', () {
      for (final text in ['meet at 10:30', 'ratio 3:1', 'hello :-) bye']) {
        expect(splitEmoji(text, _emojis), [TextChunk(text)], reason: text);
      }
    });

    test('handles several emoji, including adjacent ones', () {
      expect(splitEmoji(':blobcat::party:', _emojis), [
        const EmojiRun('blobcat', _blobcat),
        const EmojiRun('party', _party),
      ]);
    });

    test('handles an emoji at the very start and end', () {
      expect(splitEmoji(':party: yes :party:', _emojis), [
        const EmojiRun('party', _party),
        const TextChunk(' yes '),
        const EmojiRun('party', _party),
      ]);
    });

    test('empty text yields nothing', () {
      expect(splitEmoji('', _emojis), isEmpty);
    });
  });

  group('Mastodon supplies them', () {
    Future<FeedItem> fetch(Map<String, dynamic> status) async {
      final client = MockClient((_) async =>
          http.Response.bytes(utf8.encode(jsonEncode([status])), 200));
      final items = await SourceClient.forSource(
        FeedSource(
            id: 's',
            network: Network.mastodon,
            displayName: 'M',
            params: {'instance': 'mastodon.social'}),
        client,
      ).fetchLatest();
      return items.single;
    }

    Map<String, dynamic> status({
      List<Map<String, String>> statusEmojis = const [],
      List<Map<String, String>> accountEmojis = const [],
    }) =>
        {
          'id': '1',
          'created_at': '2026-08-05T10:00:00.000Z',
          'content': '<p>hi :blobcat:</p>',
          'emojis': statusEmojis,
          'account': {
            'display_name': 'A :party:',
            'acct': 'a',
            'username': 'a',
            'emojis': accountEmojis,
          },
          'media_attachments': [],
        };

    test('carries the post\'s own emoji', () async {
      final item = await fetch(status(statusEmojis: [
        {'shortcode': 'blobcat', 'url': _blobcat},
      ]));
      expect(item.emojis, {'blobcat': _blobcat});
    });

    test('carries the author\'s too, so display names render', () async {
      final item = await fetch(status(
        statusEmojis: [
          {'shortcode': 'blobcat', 'url': _blobcat},
        ],
        accountEmojis: [
          {'shortcode': 'party', 'url': _party},
        ],
      ));
      expect(item.emojis, {'blobcat': _blobcat, 'party': _party});
    });

    test('a malformed entry is skipped rather than breaking the post',
        () async {
      final item = await fetch(status(statusEmojis: [
        {'shortcode': 'blobcat'},
        {'shortcode': 'party', 'url': _party},
      ]));
      expect(item.emojis, {'party': _party});
    });

    test('no emoji means an empty map, not a null', () async {
      expect((await fetch(status())).emojis, isEmpty);
    });
  });

  group('saved posts keep their emoji', () {
    test('round-trips through JSON', () {
      final item = FeedItem(
        id: 's:1',
        sourceId: 's',
        network: Network.mastodon,
        author: 'A :party:',
        text: 'hi :blobcat:',
        emojis: _emojis,
        createdAt: DateTime.utc(2026, 8, 1),
      );

      expect(FeedItem.fromJson(item.toJson()).emojis, _emojis);
    });

    test('a post saved before emoji existed still loads', () {
      final item = FeedItem.fromJson({
        'id': 's:1',
        'network': 'mastodon',
        'author': 'A',
        'text': 'hi',
        'createdAt': '2026-08-01T00:00:00.000Z',
      });
      expect(item.emojis, isEmpty);
    });
  });
}
