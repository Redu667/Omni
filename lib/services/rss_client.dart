import 'package:xml/xml.dart';

import '../models/feed_item.dart';
import '../models/network.dart';
import '../util/text.dart';
import 'source_client.dart';

/// RSS 2.0 and Atom feeds.
class RssClient extends SourceClient {
  const RssClient(super.source, super.httpClient);

  /// Feeds publish a fixed window of recent entries with no way to ask for
  /// older ones, so every page is the last one.
  @override
  Future<SourcePage> fetchPage({int limit = 40, String? cursor}) async {
    if (cursor != null) return const SourcePage.last([]);
    return SourcePage.last(await _fetchAll(limit));
  }

  Future<List<FeedItem>> _fetchAll(int limit) async {
    final url = source.params['url']!;
    final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');

    final res = await httpClient.get(uri, headers: {
      'User-Agent': 'Omni/0.1 (+feed reader)',
      'Accept': 'application/rss+xml, application/atom+xml, application/xml, text/xml',
    });
    if (res.statusCode != 200) {
      throw SourceFetchException(
          source.displayName, 'HTTP ${res.statusCode} from ${uri.host}');
    }

    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(res.body);
    } on XmlException {
      throw SourceFetchException(source.displayName, 'not a valid feed');
    }

    final channel = doc.findAllElements('channel').firstOrNull;
    if (channel != null) return _parseRss(channel, limit);

    final atomFeed = doc.findAllElements('feed').firstOrNull;
    if (atomFeed != null) return _parseAtom(atomFeed, limit);

    throw SourceFetchException(source.displayName, 'unrecognized feed format');
  }

  List<FeedItem> _parseRss(XmlElement channel, int limit) {
    final feedTitle =
        channel.getElement('title')?.innerText.trim() ?? source.displayName;

    return channel.findElements('item').take(limit).map((item) {
      String text(String tag) => item.getElement(tag)?.innerText.trim() ?? '';

      final images = <MediaItem>[];
      final enclosure = item.getElement('enclosure');
      if ((enclosure?.getAttribute('type') ?? '').startsWith('image')) {
        final u = enclosure!.getAttribute('url');
        if (u != null) images.add(MediaItem(url: u));
      }
      for (final mc in item.findElements('media:content')) {
        final u = mc.getAttribute('url');
        final type = mc.getAttribute('type') ?? mc.getAttribute('medium') ?? '';
        if (u != null && (type.startsWith('image') || type == 'image')) {
          images.add(MediaItem(
              url: u,
              alt: mc.getElement('media:description')?.innerText.trim()));
        }
      }

      // content:encoded carries the full article when a feed publishes it;
      // description is usually just a teaser.
      final encoded = item.getElement('content:encoded')?.innerText.trim() ?? '';
      final description = htmlToPlainText(text('description'));
      final full = htmlToPlainText(encoded.isNotEmpty ? encoded : text('description'));
      final guid = text('guid');
      final link = text('link');

      return FeedItem(
        id: '${source.id}:${guid.isNotEmpty ? guid : link}',
        sourceId: source.id,
        network: Network.rss,
        author: text('dc:creator').isNotEmpty ? text('dc:creator') : feedTitle,
        title: htmlToPlainText(text('title')),
        text: description.length > 500
            ? '${description.substring(0, 500)}…'
            : description,
        fullText: full.length > description.length ? full : null,
        url: link.isNotEmpty ? link : null,
        media: images,
        context: feedTitle,
        createdAt: parseRfc822OrIso(text('pubDate')) ?? DateTime.now().toUtc(),
      );
    }).toList(growable: false);
  }

  List<FeedItem> _parseAtom(XmlElement feed, int limit) {
    final feedTitle =
        feed.getElement('title')?.innerText.trim() ?? source.displayName;

    return feed.findElements('entry').take(limit).map((entry) {
      String text(String tag) => entry.getElement(tag)?.innerText.trim() ?? '';

      String? link;
      for (final l in entry.findElements('link')) {
        final rel = l.getAttribute('rel') ?? 'alternate';
        if (rel == 'alternate') {
          link = l.getAttribute('href');
          break;
        }
      }
      link ??= entry.findElements('link').firstOrNull?.getAttribute('href');

      final author = entry
              .getElement('author')
              ?.getElement('name')
              ?.innerText
              .trim() ??
          feedTitle;
      final summary =
          htmlToPlainText(text('summary').isNotEmpty ? text('summary') : text('content'));

      return FeedItem(
        id: '${source.id}:${text('id').isNotEmpty ? text('id') : (link ?? text('title'))}',
        sourceId: source.id,
        network: Network.rss,
        author: author,
        title: htmlToPlainText(text('title')),
        text: summary.length > 500 ? '${summary.substring(0, 500)}…' : summary,
        fullText: summary.length > 500 ? summary : null,
        url: link,
        context: feedTitle,
        createdAt: parseRfc822OrIso(
                text('published').isNotEmpty ? text('published') : text('updated')) ??
            DateTime.now().toUtc(),
      );
    }).toList(growable: false);
  }
}
