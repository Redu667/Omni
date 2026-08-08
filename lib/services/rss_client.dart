import 'dart:convert';

import 'package:xml/xml.dart';

import '../models/feed_item.dart';
import '../models/network.dart';
import '../util/text.dart';
import 'source_client.dart';

/// RSS 2.0, Atom and JSON Feed.
class RssClient extends SourceClient {
  const RssClient(super.source, super.httpClient);

  /// Validators from the last fetch of each feed, so a refresh can ask
  /// "has this changed?" rather than re-downloading it. Cheap for us and
  /// polite to publishers, who are the ones paying for the bandwidth.
  static final _validators = <String, ({String? etag, String? lastModified})>{};

  /// Items from the last successful fetch, returned unchanged on a 304.
  static final _lastItems = <String, List<FeedItem>>{};

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

    final cached = _validators[source.id];
    final res = await httpClient.get(uri, headers: {
      'User-Agent': 'Omni/1.0 (+feed reader)',
      'Accept': 'application/rss+xml, application/atom+xml, application/feed+json, '
          'application/json, application/xml, text/xml',
      if (cached?.etag != null) 'If-None-Match': cached!.etag!,
      if (cached?.lastModified != null)
        'If-Modified-Since': cached!.lastModified!,
    });

    // Unchanged since last time — reuse what we already parsed.
    if (res.statusCode == 304) {
      return _lastItems[source.id] ?? const [];
    }

    if (res.statusCode != 200) {
      throw SourceFetchException(
          source.displayName, 'HTTP ${res.statusCode} from ${uri.host}');
    }

    final etag = res.headers['etag'];
    final lastModified = res.headers['last-modified'];
    if (etag != null || lastModified != null) {
      _validators[source.id] = (etag: etag, lastModified: lastModified);
    }

    // JSON Feed is a third format with the same job; publishers who use it
    // usually offer nothing else.
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (body.trimLeft().startsWith('{')) {
      final parsed = _parseJsonFeed(body, limit);
      if (parsed != null) return _lastItems[source.id] = parsed;
      throw SourceFetchException(source.displayName, 'not a valid feed');
    }

    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(body);
    } on XmlException {
      throw SourceFetchException(source.displayName, 'not a valid feed');
    }

    final channel = doc.findAllElements('channel').firstOrNull;
    if (channel != null) {
      return _lastItems[source.id] = _parseRss(channel, limit);
    }

    final atomFeed = doc.findAllElements('feed').firstOrNull;
    if (atomFeed != null) {
      return _lastItems[source.id] = _parseAtom(atomFeed, limit);
    }

    throw SourceFetchException(source.displayName, 'unrecognized feed format');
  }

  List<FeedItem> _parseRss(XmlElement channel, int limit) {
    final feedTitle =
        channel.getElement('title')?.innerText.trim() ?? source.displayName;
    // Podcast episodes rarely carry their own art; the show's stands in.
    final channelImage =
        channel.getElement('itunes:image')?.getAttribute('href') ??
            channel.getElement('image')?.getElement('url')?.innerText.trim();

    return channel.findElements('item').take(limit).map((item) {
      String text(String tag) => item.getElement(tag)?.innerText.trim() ?? '';

      final images = <MediaItem>[];
      // An enclosure is a picture, a video, or — on a podcast feed — the
      // episode itself, which was previously thrown away.
      for (final enclosure in item.findElements('enclosure')) {
        final attached = _enclosureFrom(
          url: enclosure.getAttribute('url'),
          type: enclosure.getAttribute('type'),
          durationText: item.getElement('itunes:duration')?.innerText,
          thumbnailUrl: item
                  .getElement('itunes:image')
                  ?.getAttribute('href') ??
              channelImage,
        );
        if (attached != null) images.add(attached);
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

  /// Turns one enclosure into media, or null when it's something Omni has
  /// no way to present (a PDF, a torrent).
  static MediaItem? _enclosureFrom({
    required String? url,
    required String? type,
    String? durationText,
    String? thumbnailUrl,
  }) {
    if (url == null || url.isEmpty) return null;
    final mime = type ?? '';

    final kind = mime.startsWith('image')
        ? MediaKind.image
        : mime.startsWith('video')
            ? MediaKind.video
            : mime.startsWith('audio')
                ? MediaKind.audio
                : null;
    if (kind == null) return null;

    return MediaItem(
      url: url,
      kind: kind,
      thumbnailUrl: kind == MediaKind.image ? null : thumbnailUrl,
      durationSeconds: parseDurationSeconds(durationText),
    );
  }

  /// JSON Feed (jsonfeed.org). Returns null when the body is JSON but not a
  /// feed, so the caller can say so rather than throwing a decode error.
  List<FeedItem>? _parseJsonFeed(String body, int limit) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final entries = decoded['items'];
    if (entries is! List) return null;

    final feedTitle = decoded['title'] as String? ?? source.displayName;
    final feedIcon = decoded['icon'] as String? ?? decoded['favicon'] as String?;

    return [
      for (final raw in entries.take(limit).cast<Map<String, dynamic>>())
        () {
          final html = raw['content_html'] as String?;
          final plain = raw['content_text'] as String? ??
              htmlToPlainText(html ?? '');
          final summary = raw['summary'] as String? ?? plain;
          final url = raw['url'] as String? ?? raw['external_url'] as String?;

          final authors = raw['authors'] as List?;
          final author = (raw['author'] as Map<String, dynamic>?)?['name']
                  as String? ??
              (authors == null || authors.isEmpty
                  ? null
                  : (authors.first as Map<String, dynamic>)['name'] as String?);

          return FeedItem(
            id: '${source.id}:${raw['id'] ?? url ?? raw['title']}',
            sourceId: source.id,
            network: Network.rss,
            author: author ?? feedTitle,
            title: raw['title'] as String?,
            text: summary.length > 500
                ? '${summary.substring(0, 500)}…'
                : summary,
            fullText: plain.length > summary.length ? plain : null,
            url: url,
            media: [
              if (raw['image'] case final String image) MediaItem(url: image),
              for (final a in (raw['attachments'] as List? ?? const [])
                  .cast<Map<String, dynamic>>())
                if (_enclosureFrom(
                      url: a['url'] as String?,
                      type: a['mime_type'] as String?,
                      thumbnailUrl: raw['image'] as String? ?? feedIcon,
                    )
                    case final attached?)
                  attached,
            ],
            context: feedTitle,
            createdAt: parseRfc822OrIso(
                    raw['date_published'] as String? ??
                        raw['date_modified'] as String? ??
                        '') ??
                DateTime.now().toUtc(),
          );
        }(),
    ];
  }
}
